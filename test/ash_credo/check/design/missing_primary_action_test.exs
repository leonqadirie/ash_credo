defmodule AshCredo.Check.Design.MissingPrimaryActionTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Design.MissingPrimaryAction

  test "reports issue when multiple actions of same type with no primary" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        create :create do
          accept [:title]
        end

        create :import do
          accept [:title, :body]
        end
      end
    end
    """

    assert [issue] = run_check(MissingPrimaryAction, source)
    assert issue.message =~ "create"
    assert issue.message =~ "primary?"
  end

  test "no issue when primary action is declared" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        create :create do
          primary? true
          accept [:title]
        end

        create :import do
          accept [:title, :body]
        end
      end
    end
    """

    assert [] = run_check(MissingPrimaryAction, source)
  end

  test "no issue when primary action is declared inline alongside a do block" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        create :create, primary?: true do
          accept [:title]
        end

        create :import do
          accept [:title, :body]
        end
      end
    end
    """

    assert [] = run_check(MissingPrimaryAction, source)
  end

  test "no issue when only one action of each type" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        create :create do
          accept [:title]
        end

        read :read do
          primary? true
        end
      end
    end
    """

    assert [] = run_check(MissingPrimaryAction, source)
  end

  test "reports issues for multiple types missing primary" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        create :create do
          accept [:title]
        end

        create :import do
          accept [:title, :body]
        end

        read :list do
          filter expr(published == true)
        end

        read :mine do
          filter expr(author_id == ^actor(:id))
        end
      end
    end
    """

    issues = run_check(MissingPrimaryAction, source)
    assert length(issues) == 2
    types = Enum.map(issues, & &1.trigger)
    assert "create" in types
    assert "read" in types
  end

  test "ignores non-Ash modules" do
    source = """
    defmodule MyApp.Utils do
      def hello, do: :world
    end
    """

    assert [] = run_check(MissingPrimaryAction, source)
  end

  test "no issue when no actions section" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog
    end
    """

    assert [] = run_check(MissingPrimaryAction, source)
  end
end
