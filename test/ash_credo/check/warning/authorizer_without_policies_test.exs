defmodule AshCredo.Check.Warning.AuthorizerWithoutPoliciesTest do
  use AshCredo.CheckCase, clear_cache: true

  alias AshCredo.Check.Warning.AuthorizerWithoutPolicies

  # Tests reference real fixture modules from `test/support/fixtures/ash_fixtures.ex`:
  #
  #   * `AshCredoFixtures.Blog.WithAuthorizer` - declares `Ash.Policy.Authorizer`
  #     but defines NO policies block. Failure-path fixture.
  #   * `AshCredoFixtures.Blog.Post`            - has no authorizer at all.
  #     Happy-path fixture (check should silently skip).
  #   * `AshCredoFixtures.Blog.WithAuthorizerAndPolicies` - declares the
  #     authorizer AND a non-empty `policies` block. Happy-path fixture.

  test "reports an issue when Ash.Policy.Authorizer is declared but no policies exist" do
    source = """
    defmodule AshCredoFixtures.Blog.WithAuthorizer do
      use Ash.Resource, domain: AshCredoFixtures.Blog
    end
    """

    assert [issue] = run_check(AuthorizerWithoutPolicies, source)
    assert issue.message =~ "no policies defined"
    assert issue.trigger == "Ash.Policy.Authorizer"
  end

  test "no issue when no authorizer is declared" do
    source = """
    defmodule AshCredoFixtures.Blog.Post do
      use Ash.Resource, domain: AshCredoFixtures.Blog
    end
    """

    assert [] = run_check(AuthorizerWithoutPolicies, source)
  end

  test "no issue when the authorizer is declared and policies exist" do
    source = """
    defmodule AshCredoFixtures.Blog.WithAuthorizerAndPolicies do
      use Ash.Resource, domain: AshCredoFixtures.Blog
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

  test "emits a not-loadable config issue for an unknown resource" do
    source = """
    defmodule Totally.Fake.Resource do
      use Ash.Resource, domain: AshCredoFixtures.Blog
    end
    """

    assert [issue] = run_check(AuthorizerWithoutPolicies, source)
    assert issue.message =~ "Could not load"
    assert issue.message =~ "Totally.Fake.Resource"
  end
end
