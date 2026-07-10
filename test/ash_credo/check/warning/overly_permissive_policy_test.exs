defmodule AshCredo.Check.Warning.OverlyPermissivePolicyTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Warning.OverlyPermissivePolicy

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
    assert issue.trigger == "authorize_if always()"
    assert issue.line_no == 5
  end

  test "reports issue when authorize_if always() carries trailing options" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, authorizers: [Ash.Policy.Authorizer]

      policies do
        policy always() do
          authorize_if always(), name: "everyone"
        end
      end
    end
    """

    assert [issue] = run_check(OverlyPermissivePolicy, source)
    assert issue.message =~ "Unscoped policy"
    assert issue.trigger == "authorize_if always()"
  end

  test "no issue when another authorize_if check carries trailing options" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, authorizers: [Ash.Policy.Authorizer]

      policies do
        policy always() do
          authorize_if actor_attribute_equals(:admin, true), name: "admins"
        end
      end
    end
    """

    assert [] = run_check(OverlyPermissivePolicy, source)
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
    assert issue.trigger == "authorize_if always()"
    assert issue.line_no == 5
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
    assert issue.trigger == "authorize_if always()"
    # The nested policy sits one line below the enclosing policy_group.
    assert issue.line_no == 6
  end

  test "no issue when the enclosing policy_group has a restrictive condition" do
    # Ash adds the group condition to every policy the group contains, so
    # the inner policy is effectively scoped to admins.
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, authorizers: [Ash.Policy.Authorizer]

      policies do
        policy_group actor_attribute_equals(:role, :admin) do
          policy do
            authorize_if always()
          end
        end
      end
    end
    """

    assert [] = run_check(OverlyPermissivePolicy, source)
  end

  test "reports issue when the enclosing policy_group condition is always()" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, authorizers: [Ash.Policy.Authorizer]

      policies do
        policy_group always() do
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

  test "no issue when a nested policy_group carries the restrictive condition" do
    # policy_group is recursive; the inner group's condition scopes the policy.
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, authorizers: [Ash.Policy.Authorizer]

      policies do
        policy_group always() do
          policy_group actor_attribute_equals(:role, :admin) do
            policy do
              authorize_if always()
            end
          end
        end
      end
    end
    """

    assert [] = run_check(OverlyPermissivePolicy, source)
  end

  test "reports issue for an unscoped policy nested two policy_groups deep" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, authorizers: [Ash.Policy.Authorizer]

      policies do
        policy_group always() do
          policy_group expr(true) do
            policy do
              authorize_if always()
            end
          end
        end
      end
    end
    """

    assert [issue] = run_check(OverlyPermissivePolicy, source)
    assert issue.line_no == 7
  end

  test "no issue for the allow-all-except pattern (forbid_if before authorize_if always())" do
    # Checks apply top to bottom and the first decision wins, so the
    # forbid_if guards the authorize_if always().
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, authorizers: [Ash.Policy.Authorizer]

      policies do
        policy always() do
          forbid_if actor_attribute_equals(:banned, true)
          authorize_if always()
        end
      end
    end
    """

    assert [] = run_check(OverlyPermissivePolicy, source)
  end

  test "no issue when forbid_unless precedes authorize_if always()" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, authorizers: [Ash.Policy.Authorizer]

      policies do
        policy always() do
          forbid_unless actor_present()
          authorize_if always()
        end
      end
    end
    """

    assert [] = run_check(OverlyPermissivePolicy, source)
  end

  test "reports issue when the only guard is a forbid that can never fire" do
    # forbid_unless always()/expr(true) never forbids; forbid_if
    # never()/expr(false) never fires - these are not real guards.
    for guard <- [
          "forbid_unless always()",
          "forbid_unless expr(true)",
          "forbid_if never()",
          "forbid_if expr(false)"
        ] do
      source = """
      defmodule MyApp.Post do
        use Ash.Resource, domain: MyApp.Blog, authorizers: [Ash.Policy.Authorizer]

        policies do
          policy always() do
            #{guard}
            authorize_if always()
          end
        end
      end
      """

      assert [issue] = run_check(OverlyPermissivePolicy, source)
      assert issue.message =~ "Unscoped policy"
    end
  end

  test "reports issue when the no-op guard carries a trailing options list" do
    # Checks accept options (`name:`); they do not make a dead guard real.
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, authorizers: [Ash.Policy.Authorizer]

      policies do
        policy always() do
          forbid_if never(), name: "documentation no-op"
          authorize_if always()
        end
      end
    end
    """

    assert [issue] = run_check(OverlyPermissivePolicy, source)
    assert issue.message =~ "Unscoped policy"
  end

  test "no issue when a real guard carries a trailing options list" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, authorizers: [Ash.Policy.Authorizer]

      policies do
        policy always() do
          forbid_if actor_attribute_equals(:banned, true), name: "no banned actors"
          authorize_if always()
        end
      end
    end
    """

    assert [] = run_check(OverlyPermissivePolicy, source)
  end

  test "reports issue when the guard is a bare boolean no-op" do
    # Ash accepts booleans as checks; forbid_if false and forbid_unless true
    # never forbid anything.
    for guard <- ["forbid_if false", "forbid_unless true"] do
      source = """
      defmodule MyApp.Post do
        use Ash.Resource, domain: MyApp.Blog, authorizers: [Ash.Policy.Authorizer]

        policies do
          policy always() do
            #{guard}
            authorize_if always()
          end
        end
      end
      """

      assert [issue] = run_check(OverlyPermissivePolicy, source)
      assert issue.message =~ "Unscoped policy"
    end
  end

  test "reports issue for an unconditioned policy declared with entity options" do
    # `policy description: "..." do` passes options, not a condition - the
    # policy still defaults to applying everywhere.
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, authorizers: [Ash.Policy.Authorizer]

      policies do
        policy description: "everyone can do everything" do
          authorize_if always()
        end
      end
    end
    """

    assert [issue] = run_check(OverlyPermissivePolicy, source)
    assert issue.message =~ "Unscoped policy"
  end

  test "no issue when the condition is passed via the condition option" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, authorizers: [Ash.Policy.Authorizer]

      policies do
        policy condition: actor_attribute_equals(:role, :admin), description: "admins" do
          authorize_if always()
        end
      end
    end
    """

    assert [] = run_check(OverlyPermissivePolicy, source)
  end

  test "reports issue when the condition option is itself unscoped" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, authorizers: [Ash.Policy.Authorizer]

      policies do
        policy condition: always(), description: "everyone" do
          authorize_if always()
        end
      end
    end
    """

    assert [issue] = run_check(OverlyPermissivePolicy, source)
    assert issue.message =~ "Unscoped policy"
  end

  test "reports issue when authorize_if always() precedes the forbid check" do
    # The authorize_if always() decides first; the forbid_if below it never
    # runs, so the policy is genuinely all-permissive.
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, authorizers: [Ash.Policy.Authorizer]

      policies do
        policy always() do
          authorize_if always()
          forbid_if actor_attribute_equals(:banned, true)
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

  test "reports issue when policy has no condition argument" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, authorizers: [Ash.Policy.Authorizer]

      policies do
        policy do
          authorize_if always()
        end
      end
    end
    """

    assert [issue] = run_check(OverlyPermissivePolicy, source)
    assert issue.message =~ "Unscoped policy"
    assert issue.trigger == "authorize_if always()"
    assert issue.line_no == 5
  end

  test "reports issue when condition is a list containing only always()" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, authorizers: [Ash.Policy.Authorizer]

      policies do
        policy [always()] do
          authorize_if always()
        end
      end
    end
    """

    assert [issue] = run_check(OverlyPermissivePolicy, source)
    assert issue.message =~ "Unscoped policy"
    assert issue.trigger == "authorize_if always()"
    assert issue.line_no == 5
  end

  test "reports issue when bypass condition is a list containing only always()" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, authorizers: [Ash.Policy.Authorizer]

      policies do
        bypass [always()] do
          authorize_if always()
        end
      end
    end
    """

    assert [issue] = run_check(OverlyPermissivePolicy, source)
    assert issue.message =~ "Bypass"
  end

  test "reports issue when body-level condition is always()" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, authorizers: [Ash.Policy.Authorizer]

      policies do
        policy do
          condition always()
          authorize_if always()
        end
      end
    end
    """

    assert [issue] = run_check(OverlyPermissivePolicy, source)
    assert issue.message =~ "Unscoped policy"
  end

  test "reports issue when body-level condition is expr(true)" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, authorizers: [Ash.Policy.Authorizer]

      policies do
        policy do
          condition expr(true)
          authorize_if always()
        end
      end
    end
    """

    assert [issue] = run_check(OverlyPermissivePolicy, source)
    assert issue.message =~ "Unscoped policy"
  end

  test "no issue when list condition mixes always() with a restrictive check" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, authorizers: [Ash.Policy.Authorizer]

      policies do
        policy [actor_attribute_equals(:role, :admin), always()] do
          authorize_if always()
        end
      end
    end
    """

    assert [] = run_check(OverlyPermissivePolicy, source)
  end

  test "no issue when body-level condition is restrictive" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, authorizers: [Ash.Policy.Authorizer]

      policies do
        policy do
          condition actor_attribute_equals(:role, :admin)
          authorize_if always()
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
