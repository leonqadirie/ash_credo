defmodule AshCredo.Check.Design.MissingIdentityTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Design.MissingIdentity
  alias AshCredo.Introspection.Compiled, as: CompiledIntrospection

  # Tests reference real fixture modules from `test/support/fixtures/ash_fixtures.ex`:
  #
  #   * `AshCredoFixtures.Accounts.Member`  — has `:email` and `:username`
  #     attributes, no identities. Failure-path fixture for the migration.
  #   * `AshCredoFixtures.Accounts.Profile` — has `:email` attribute AND
  #     `:unique_email` identity covering it. Happy-path fixture.

  setup do
    CompiledIntrospection.clear_cache()
    :ok
  end

  test "reports an issue per uncovered candidate attribute" do
    source = """
    defmodule AshCredoFixtures.Accounts.Member do
      use Ash.Resource, domain: AshCredoFixtures.Accounts
    end
    """

    issues = run_check(MissingIdentity, source)

    triggers = issues |> MapSet.new(& &1.trigger)
    assert MapSet.equal?(triggers, MapSet.new(~w(email username)))

    for issue <- issues do
      assert issue.message =~ "AshCredoFixtures.Accounts.Member"
      assert issue.message =~ "uniqueness identity"
      assert issue.message =~ "identity :unique_"
    end
  end

  test "no issue when the candidate attribute has a covering identity" do
    source = """
    defmodule AshCredoFixtures.Accounts.Profile do
      use Ash.Resource, domain: AshCredoFixtures.Accounts
    end
    """

    assert [] = run_check(MissingIdentity, source)
  end

  test "respects the configurable identity_candidates list" do
    source = """
    defmodule AshCredoFixtures.Accounts.Member do
      use Ash.Resource, domain: AshCredoFixtures.Accounts
    end
    """

    # Member has :email and :username; restrict candidates to slug/handle/phone
    # → neither attribute matches, no issues fire.
    assert [] =
             run_check(MissingIdentity, source, identity_candidates: ~w(slug handle phone)a)
  end

  test "ignores non-Ash modules" do
    source = """
    defmodule MyApp.Utils do
      def hello, do: :world
    end
    """

    assert [] = run_check(MissingIdentity, source)
  end

  test "emits a not-loadable config issue for an unknown resource" do
    source = """
    defmodule Totally.Fake.Resource do
      use Ash.Resource, domain: AshCredoFixtures.Accounts
    end
    """

    assert [issue] = run_check(MissingIdentity, source)
    assert issue.message =~ "Could not load"
    assert issue.message =~ "Totally.Fake.Resource"
  end
end
