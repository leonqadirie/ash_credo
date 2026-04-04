defmodule AshCredo.Check.Ash.SensitiveAttributeExposedTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Ash.SensitiveAttributeExposed

  test "reports issue for unprotected sensitive attribute" do
    source = """
    defmodule MyApp.User do
      use Ash.Resource, domain: MyApp.Accounts

      attributes do
        uuid_primary_key :id
        attribute :email, :string
        attribute :hashed_password, :string
      end
    end
    """

    assert [issue] = run_check(SensitiveAttributeExposed, source)
    assert issue.message =~ "hashed_password"
    assert issue.message =~ "sensitive?"
  end

  test "no issue when sensitive attribute marked sensitive" do
    source = """
    defmodule MyApp.User do
      use Ash.Resource, domain: MyApp.Accounts

      attributes do
        uuid_primary_key :id
        attribute :email, :string
        attribute :hashed_password, :string, sensitive?: true
      end
    end
    """

    assert [] = run_check(SensitiveAttributeExposed, source)
  end

  test "reports multiple sensitive attributes" do
    source = """
    defmodule MyApp.User do
      use Ash.Resource, domain: MyApp.Accounts

      attributes do
        uuid_primary_key :id
        attribute :password, :string
        attribute :api_key, :string
        attribute :token, :string
      end
    end
    """

    issues = run_check(SensitiveAttributeExposed, source)
    assert length(issues) == 3
  end

  test "ignores non-sensitive attributes" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      attributes do
        uuid_primary_key :id
        attribute :title, :string
        attribute :body, :string
      end
    end
    """

    assert [] = run_check(SensitiveAttributeExposed, source)
  end

  test "ignores non-Ash modules" do
    source = """
    defmodule MyApp.Utils do
      def password, do: "secret"
    end
    """

    assert [] = run_check(SensitiveAttributeExposed, source)
  end
end
