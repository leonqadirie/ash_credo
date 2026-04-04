defmodule AshCredo.Check.Design.MissingIdentityTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Design.MissingIdentity

  test "reports issue for email without identity" do
    source = """
    defmodule MyApp.User do
      use Ash.Resource, domain: MyApp.Accounts

      attributes do
        uuid_primary_key :id
        attribute :email, :ci_string, allow_nil?: false
      end
    end
    """

    assert [issue] = run_check(MissingIdentity, source)
    assert issue.message =~ "email"
    assert issue.message =~ "identity"
  end

  test "no issue when identity exists for email" do
    source = """
    defmodule MyApp.User do
      use Ash.Resource, domain: MyApp.Accounts

      attributes do
        uuid_primary_key :id
        attribute :email, :ci_string, allow_nil?: false
      end

      identities do
        identity :unique_email, [:email]
      end
    end
    """

    assert [] = run_check(MissingIdentity, source)
  end

  test "no issue for non-candidate attributes" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      attributes do
        uuid_primary_key :id
        attribute :title, :string
      end
    end
    """

    assert [] = run_check(MissingIdentity, source)
  end

  test "reports multiple missing identities" do
    source = """
    defmodule MyApp.User do
      use Ash.Resource, domain: MyApp.Accounts

      attributes do
        uuid_primary_key :id
        attribute :email, :ci_string
        attribute :username, :string
      end
    end
    """

    issues = run_check(MissingIdentity, source)
    assert length(issues) == 2
  end

  test "ignores non-Ash modules" do
    source = """
    defmodule MyApp.Utils do
      def email, do: "test@example.com"
    end
    """

    assert [] = run_check(MissingIdentity, source)
  end
end
