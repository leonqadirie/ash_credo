defmodule AshCredo.Check.Warning.AuthorizerWithoutPoliciesTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Warning.AuthorizerWithoutPolicies

  test "reports issue when authorizer present but no policies" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource,
        domain: MyApp.Blog,
        authorizers: [Ash.Policy.Authorizer]

      attributes do
        uuid_primary_key :id
      end
    end
    """

    assert [issue] = run_check(AuthorizerWithoutPolicies, source)
    assert issue.message =~ "no policies defined"
  end

  test "reports issue when policies block is empty" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource,
        domain: MyApp.Blog,
        authorizers: [Ash.Policy.Authorizer]

      policies do
      end
    end
    """

    assert [issue] = run_check(AuthorizerWithoutPolicies, source)
    assert issue.message =~ "no policies defined"
  end

  test "no issue when authorizer and policies both present" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource,
        domain: MyApp.Blog,
        authorizers: [Ash.Policy.Authorizer]

      attributes do
        uuid_primary_key :id
      end

      policies do
        policy action_type(:read) do
          authorize_if always()
        end
      end
    end
    """

    assert [] = run_check(AuthorizerWithoutPolicies, source)
  end

  test "reports issue when policies section has only settings" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource,
        domain: MyApp.Blog,
        authorizers: [Ash.Policy.Authorizer]

      policies do
        default_access_type :runtime
      end
    end
    """

    assert [issue] = run_check(AuthorizerWithoutPolicies, source)
    assert issue.message =~ "no policies defined"
  end

  test "no issue when no authorizer" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      attributes do
        uuid_primary_key :id
      end
    end
    """

    assert [] = run_check(AuthorizerWithoutPolicies, source)
  end

  test "ignores non-Ash modules" do
    source = """
    defmodule MyApp.Utils do
      def hello, do: :world
    end
    """

    assert [] = run_check(AuthorizerWithoutPolicies, source)
  end
end
