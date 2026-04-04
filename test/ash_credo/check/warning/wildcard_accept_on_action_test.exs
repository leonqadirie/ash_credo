defmodule AshCredo.Check.Warning.WildcardAcceptOnActionTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Warning.WildcardAcceptOnAction

  test "reports issue for accept :* on create" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        create :create do
          accept :*
        end
      end
    end
    """

    assert [issue] = run_check(WildcardAcceptOnAction, source)
    assert issue.message =~ "accept :*"
  end

  test "reports issue for accept :* on update" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        update :update do
          accept :*
        end
      end
    end
    """

    assert [_issue] = run_check(WildcardAcceptOnAction, source)
  end

  test "no issue for explicit accept list" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        create :create do
          accept [:title, :body]
        end
      end
    end
    """

    assert [] = run_check(WildcardAcceptOnAction, source)
  end

  test "reports issue for wildcard writable default actions" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        defaults [create: :*, update: :*]
      end
    end
    """

    issues = run_check(WildcardAcceptOnAction, source)

    assert length(issues) == 2
    assert Enum.any?(issues, &String.contains?(&1.message, "Default `create` action"))
    assert Enum.any?(issues, &String.contains?(&1.message, "Default `update` action"))
  end

  test "reports issue for inline accept: :* on create" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        create :create, accept: :*
      end
    end
    """

    assert [issue] = run_check(WildcardAcceptOnAction, source)
    assert issue.message =~ "accept :*"
  end

  test "reports issue for default_accept :*" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        default_accept :*
        create :create do
          accept [:title]
        end
      end
    end
    """

    assert [issue] = run_check(WildcardAcceptOnAction, source)
    assert issue.message =~ "default_accept"
  end

  test "ignores read and destroy actions" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        read :read
        destroy :destroy
      end
    end
    """

    assert [] = run_check(WildcardAcceptOnAction, source)
  end

  test "ignores non-Ash modules" do
    source = """
    defmodule MyApp.Utils do
      def accept(:*), do: :ok
    end
    """

    assert [] = run_check(WildcardAcceptOnAction, source)
  end
end
