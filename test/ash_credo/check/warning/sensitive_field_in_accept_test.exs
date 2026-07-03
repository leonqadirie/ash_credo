defmodule AshCredo.Check.Warning.SensitiveFieldInAcceptTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Warning.SensitiveFieldInAccept

  test "reports issue for is_admin in accept" do
    source = """
    defmodule MyApp.User do
      use Ash.Resource, domain: MyApp.Accounts

      actions do
        create :register do
          accept [:name, :email, :is_admin]
        end
      end
    end
    """

    assert [issue] = run_check(SensitiveFieldInAccept, source)
    assert issue.message =~ "is_admin"
    assert issue.message =~ "privilege escalation"
  end

  test "reports multiple dangerous fields" do
    source = """
    defmodule MyApp.User do
      use Ash.Resource, domain: MyApp.Accounts

      actions do
        update :update do
          accept [:name, :is_admin, :permissions]
        end
      end
    end
    """

    issues = run_check(SensitiveFieldInAccept, source)
    assert [_, _] = issues
    triggers = Enum.map(issues, & &1.trigger)
    assert "is_admin" in triggers
    assert "permissions" in triggers
    assert sorted_lines(issues) == [6, 6]
  end

  test "reports issue for inline accept with dangerous fields" do
    source = """
    defmodule MyApp.User do
      use Ash.Resource, domain: MyApp.Accounts

      actions do
        update :update, accept: [:name, :is_admin]
      end
    end
    """

    assert [issue] = run_check(SensitiveFieldInAccept, source)
    assert issue.message =~ "is_admin"
  end

  test "reports issue for inline accept with dangerous fields and a do block" do
    source = """
    defmodule MyApp.User do
      use Ash.Resource, domain: MyApp.Accounts

      actions do
        update :update, accept: [:name, :is_admin] do
          description "Update a user"
        end
      end
    end
    """

    assert [issue] = run_check(SensitiveFieldInAccept, source)
    assert issue.message =~ "is_admin"
  end

  test "reports issue for dangerous fields accepted by a soft destroy" do
    source = """
    defmodule MyApp.User do
      use Ash.Resource, domain: MyApp.Accounts

      actions do
        destroy :archive do
          soft? true
          accept [:archived_reason, :is_admin]
        end
      end
    end
    """

    assert [issue] = run_check(SensitiveFieldInAccept, source)
    assert issue.message =~ "is_admin"
    assert issue.line_no == 7
  end

  test "no issue for dangerous fields on a hard destroy (Ash resets its accept)" do
    source = """
    defmodule MyApp.User do
      use Ash.Resource, domain: MyApp.Accounts

      actions do
        destroy :purge do
          accept [:is_admin]
        end
      end
    end
    """

    assert [] = run_check(SensitiveFieldInAccept, source)
  end

  test "reports issue for dangerous fields in defaults" do
    source = """
    defmodule MyApp.User do
      use Ash.Resource, domain: MyApp.Accounts

      actions do
        defaults [create: [:name, :is_admin]]
      end
    end
    """

    assert [issue] = run_check(SensitiveFieldInAccept, source)
    assert issue.message =~ "is_admin"
  end

  test "reports issue for dangerous fields in default_accept" do
    source = """
    defmodule MyApp.User do
      use Ash.Resource, domain: MyApp.Accounts

      actions do
        default_accept [:name, :is_admin]
        create :register
      end
    end
    """

    assert [issue] = run_check(SensitiveFieldInAccept, source)
    assert issue.message =~ "is_admin"
  end

  test "matches dangerous fields by regex when configured" do
    source = """
    defmodule MyApp.User do
      use Ash.Resource, domain: MyApp.Accounts

      actions do
        create :register do
          accept [:name, :reset_token, :api_token]
        end
      end
    end
    """

    issues = run_check(SensitiveFieldInAccept, source, dangerous_fields: [~r/_token$/])
    assert [_, _] = issues
    triggers = Enum.map(issues, & &1.trigger)
    assert "reset_token" in triggers
    assert "api_token" in triggers
    assert sorted_lines(issues) == [6, 6]
  end

  test "regex and atom entries can be mixed" do
    source = """
    defmodule MyApp.User do
      use Ash.Resource, domain: MyApp.Accounts

      actions do
        create :register do
          accept [:name, :is_admin, :reset_token]
        end
      end
    end
    """

    issues = run_check(SensitiveFieldInAccept, source, dangerous_fields: [:is_admin, ~r/_token$/])
    triggers = Enum.map(issues, & &1.trigger)
    assert "is_admin" in triggers
    assert "reset_token" in triggers
  end

  test "no issue for safe fields" do
    source = """
    defmodule MyApp.User do
      use Ash.Resource, domain: MyApp.Accounts

      actions do
        create :register do
          accept [:name, :email]
        end
      end
    end
    """

    assert [] = run_check(SensitiveFieldInAccept, source)
  end

  test "ignores non-Ash modules" do
    source = """
    defmodule MyApp.Utils do
      def hello, do: :world
    end
    """

    assert [] = run_check(SensitiveFieldInAccept, source)
  end

  test "skips files under test directories by default" do
    source = """
    defmodule MyApp.User do
      use Ash.Resource, domain: MyApp.Accounts

      actions do
        create :register do
          accept [:name, :is_admin]
        end
      end
    end
    """

    assert [] =
             run_check(SensitiveFieldInAccept, source,
               __filename__: "test/support/user_factory.ex"
             )
  end

  test "excluded_paths can be overridden to also scan test files" do
    source = """
    defmodule MyApp.User do
      use Ash.Resource, domain: MyApp.Accounts

      actions do
        create :register do
          accept [:name, :is_admin]
        end
      end
    end
    """

    assert [issue] =
             run_check(SensitiveFieldInAccept, source,
               __filename__: "test/support/user_factory.ex",
               excluded_paths: []
             )

    assert issue.message =~ "is_admin"
  end

  describe "malformed or non-literal DSL shapes are skipped, not crashed" do
    test "a resource with no actions section yields no issues" do
      source = """
      defmodule MyApp.Post do
        use Ash.Resource, domain: MyApp.Blog

        attributes do
          uuid_primary_key :id
        end
      end
      """

      assert [] = run_check(SensitiveFieldInAccept, source)
    end

    test "a non-list `accept` value (e.g. `accept :all`) is ignored" do
      source = """
      defmodule MyApp.Post do
        use Ash.Resource, domain: MyApp.Blog

        actions do
          create :create do
            accept :all
          end
        end
      end
      """

      assert [] = run_check(SensitiveFieldInAccept, source)
    end

    test "a non-list `default_accept` value is ignored" do
      source = """
      defmodule MyApp.Post do
        use Ash.Resource, domain: MyApp.Blog

        actions do
          default_accept :all
        end
      end
      """

      assert [] = run_check(SensitiveFieldInAccept, source)
    end

    test "a regex pattern does not match a non-atom field entry" do
      source = """
      defmodule MyApp.Post do
        use Ash.Resource, domain: MyApp.Blog

        actions do
          create :create do
            accept ["api_key"]
          end
        end
      end
      """

      assert [] = run_check(SensitiveFieldInAccept, source, dangerous_fields: [~r/api_key/])
    end
  end
end
