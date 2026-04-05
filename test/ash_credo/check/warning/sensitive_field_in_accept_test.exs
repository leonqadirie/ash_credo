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
    assert length(issues) == 2
    triggers = Enum.map(issues, & &1.trigger)
    assert "is_admin" in triggers
    assert "permissions" in triggers
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
end
