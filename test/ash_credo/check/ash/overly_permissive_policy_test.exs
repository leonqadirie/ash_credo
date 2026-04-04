defmodule AshCredo.Check.Ash.OverlyPermissivePolicyTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Ash.OverlyPermissivePolicy

  test "reports issue when authorize_if always() covers all actions" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, authorizers: [Ash.Policy.Authorizer]

      policies do
        policy always() do
          authorize_if always()
        end
      end
    end
    """

    assert [issue] = run_check(OverlyPermissivePolicy, source)
    assert issue.message =~ "Unscoped policy"
  end

  test "reports issue when policy uses expr(true) as guard" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, authorizers: [Ash.Policy.Authorizer]

      policies do
        policy expr(true) do
          authorize_if always()
        end
      end
    end
    """

    assert [issue] = run_check(OverlyPermissivePolicy, source)
    assert issue.message =~ "Unscoped policy"
  end

  test "no issue when authorize_if always() restricted to reads" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, authorizers: [Ash.Policy.Authorizer]

      policies do
        policy action_type(:read) do
          authorize_if always()
        end
      end
    end
    """

    assert [] = run_check(OverlyPermissivePolicy, source)
  end

  test "reports issue for unscoped bypass with authorize_if always()" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, authorizers: [Ash.Policy.Authorizer]

      policies do
        bypass always() do
          authorize_if always()
        end
      end
    end
    """

    assert [issue] = run_check(OverlyPermissivePolicy, source)
    assert issue.message =~ "Bypass"
  end

  test "reports issue for policy inside policy_group" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, authorizers: [Ash.Policy.Authorizer]

      policies do
        policy_group do
          policy always() do
            authorize_if always()
          end
        end
      end
    end
    """

    assert [issue] = run_check(OverlyPermissivePolicy, source)
    assert issue.message =~ "Unscoped policy"
  end

  test "no issue for scoped bypass" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, authorizers: [Ash.Policy.Authorizer]

      policies do
        bypass action_type(:read) do
          authorize_if always()
        end
      end
    end
    """

    assert [] = run_check(OverlyPermissivePolicy, source)
  end

  test "no issue when no policies section" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog
    end
    """

    assert [] = run_check(OverlyPermissivePolicy, source)
  end

  test "no issue when scoped to specific actions" do
    source = """
    defmodule MyApp.User do
      use Ash.Resource, domain: MyApp.Accounts, authorizers: [Ash.Policy.Authorizer]

      policies do
        policy action([:register, :sign_in]) do
          authorize_if always()
        end
      end
    end
    """

    assert [] = run_check(OverlyPermissivePolicy, source)
  end

  test "no issue for actor-based conditions" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, authorizers: [Ash.Policy.Authorizer]

      policies do
        policy always() do
          authorize_if actor_attribute_equals(:admin, true)
        end
      end
    end
    """

    assert [] = run_check(OverlyPermissivePolicy, source)
  end

  test "ignores non-Ash modules" do
    source = """
    defmodule MyApp.Utils do
      def hello, do: :world
    end
    """

    assert [] = run_check(OverlyPermissivePolicy, source)
  end
end
