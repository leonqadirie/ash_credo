defmodule AshCredo.Check.Warning.SensitiveAttributeExposedTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Warning.SensitiveAttributeExposed

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
    assert [_, _, _] = issues
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

  test "reports new default names like access_token" do
    source = """
    defmodule MyApp.User do
      use Ash.Resource, domain: MyApp.Accounts

      attributes do
        uuid_primary_key :id
        attribute :access_token, :string
        attribute :client_secret, :string
        attribute :totp_secret, :string
        attribute :password_digest, :string
      end
    end
    """

    issues = run_check(SensitiveAttributeExposed, source)

    assert sorted_triggers(issues) == ~w(access_token client_secret password_digest totp_secret)
  end

  test "regex entry in sensitive_names matches compound attribute names" do
    source = """
    defmodule MyApp.Webhook do
      use Ash.Resource, domain: MyApp.Integrations

      attributes do
        uuid_primary_key :id
        attribute :webhook_secret, :string
        attribute :name, :string
      end
    end
    """

    assert [issue] =
             run_check(SensitiveAttributeExposed, source, sensitive_names: [~r/_secret$/])

    assert issue.trigger == "webhook_secret"
  end

  test "regex entry does not match non-matching names and atoms keep exact-match semantics" do
    source = """
    defmodule MyApp.Webhook do
      use Ash.Resource, domain: MyApp.Integrations

      attributes do
        uuid_primary_key :id
        attribute :secret_color, :string
        attribute :password, :string
        attribute :user_password, :string
      end
    end
    """

    issues =
      run_check(SensitiveAttributeExposed, source, sensitive_names: [:password, ~r/_secret$/])

    assert [issue] = issues
    assert issue.trigger == "password"
  end

  test "regex-matched attribute marked sensitive stays silent" do
    source = """
    defmodule MyApp.Webhook do
      use Ash.Resource, domain: MyApp.Integrations

      attributes do
        uuid_primary_key :id
        attribute :webhook_secret, :string, sensitive?: true
      end
    end
    """

    assert [] =
             run_check(SensitiveAttributeExposed, source, sensitive_names: [~r/_secret$/])
  end

  test "custom sensitive_names param fully replaces defaults" do
    source = """
    defmodule MyApp.User do
      use Ash.Resource, domain: MyApp.Accounts

      attributes do
        uuid_primary_key :id
        attribute :password, :string
        attribute :pin_code, :string
      end
    end
    """

    assert [issue] = run_check(SensitiveAttributeExposed, source, sensitive_names: [:pin_code])
    assert issue.trigger == "pin_code"
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
