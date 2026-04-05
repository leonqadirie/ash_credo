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

  test "reports issue when Ash.Policy.Authorizer appears alongside other authorizers" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource,
        domain: MyApp.Blog,
        authorizers: [SomeOtherAuthorizer, Ash.Policy.Authorizer]

      attributes do
        uuid_primary_key :id
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

  test "does not match alias declarations outside the authorizers option" do
    source = """
    defmodule MyApp.Post do
      alias Ash.Policy.Authorizer

      use Ash.Resource, domain: MyApp.Blog

      attributes do
        uuid_primary_key :id
      end
    end
    """

    assert [] = run_check(AuthorizerWithoutPolicies, source)
  end

  test "reports issue when authorizer is referenced through a local alias" do
    source = """
    defmodule MyApp.Post do
      alias Ash.Policy.Authorizer

      use Ash.Resource,
        domain: MyApp.Blog,
        authorizers: [Authorizer]

      attributes do
        uuid_primary_key :id
      end
    end
    """

    assert [issue] = run_check(AuthorizerWithoutPolicies, source)
    assert issue.message =~ "no policies defined"
  end

  test "reports issue when authorizer is referenced through an explicit alias" do
    source = """
    defmodule MyApp.Post do
      alias Ash.Policy.Authorizer, as: PolicyAuthorizer

      use Ash.Resource,
        domain: MyApp.Blog,
        authorizers: [PolicyAuthorizer]

      attributes do
        uuid_primary_key :id
      end
    end
    """

    assert [issue] = run_check(AuthorizerWithoutPolicies, source)
    assert issue.message =~ "no policies defined"
  end

  test "reports issue when authorizer is referenced through a grouped alias" do
    source = """
    defmodule MyApp.Post do
      alias Ash.Policy.{Authorizer, Check}

      use Ash.Resource,
        domain: MyApp.Blog,
        authorizers: [Authorizer]

      attributes do
        uuid_primary_key :id
      end
    end
    """

    assert [issue] = run_check(AuthorizerWithoutPolicies, source)
    assert issue.message =~ "no policies defined"
  end

  test "does not match Ash.Policy.Authorizer references in regular function bodies" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      def helper, do: Ash.Policy.Authorizer
    end
    """

    assert [] = run_check(AuthorizerWithoutPolicies, source)
  end

  test "checks policies within the same resource module only" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource,
        domain: MyApp.Blog,
        authorizers: [Ash.Policy.Authorizer]

      defmodule Draft do
        use Ash.Resource,
          domain: MyApp.Blog,
          authorizers: [Ash.Policy.Authorizer]

        policies do
          policy action_type(:read) do
            authorize_if always()
          end
        end
      end
    end
    """

    assert [issue] = run_check(AuthorizerWithoutPolicies, source)
    assert issue.message =~ "no policies defined"
    assert issue.line_no == 4
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
