defmodule AshCredo.Check.Design.MissingIdentityTest do
  use AshCredo.CheckCase, clear_cache: true

  alias AshCredo.Check.Design.MissingIdentity

  # Tests reference real fixture modules from `test/support/fixtures/ash_fixtures.ex`:
  #
  #   * `AshCredoFixtures.Accounts.Member`  - has `:email` and `:username`
  #     attributes, no identities. Failure-path fixture for the migration.
  #   * `AshCredoFixtures.Accounts.Profile` - has `:email` attribute AND
  #     `:unique_email` identity covering it. Happy-path fixture.

  test "reports an issue per uncovered candidate attribute" do
    source = """
    defmodule AshCredoFixtures.Accounts.Member do
      use Ash.Resource, domain: AshCredoFixtures.Accounts
    end
    """

    issues = run_check(MissingIdentity, source)

    assert MapSet.equal?(trigger_set(issues), MapSet.new(~w(email username)))

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

  test "ignores embedded resources" do
    source = """
    defmodule AshCredoFixtures.Accounts.EmbeddedContact do
      use Ash.Resource, data_layer: :embedded
    end
    """

    assert [] = run_check(MissingIdentity, source)
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

  test "no issue when the candidate attribute is the sole primary key" do
    # EmailKey's :email IS the primary key - already unique, identity
    # would be redundant.
    source = """
    defmodule AshCredoFixtures.Accounts.EmailKey do
      use Ash.Resource, domain: AshCredoFixtures.Accounts
    end
    """

    assert [] = run_check(MissingIdentity, source)
  end

  test "still flags a candidate that is only part of a composite primary key" do
    # TenantEmailKey's key is {tenant_id, email} - the tuple is unique,
    # :email alone is not.
    source = """
    defmodule AshCredoFixtures.Accounts.TenantEmailKey do
      use Ash.Resource, domain: AshCredoFixtures.Accounts
    end
    """

    assert [issue] = run_check(MissingIdentity, source)
    assert issue.trigger == "email"
    assert issue.message =~ "unique_email"
  end
end
