defmodule AshCredo.Check.Readability.ActionMissingDescriptionTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Readability.ActionMissingDescription

  test "reports issue for action without description" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        create :create do
          accept [:title]
        end
      end
    end
    """

    assert [issue] = run_check(ActionMissingDescription, source)
    assert issue.message =~ "description"
  end

  test "no issue when description is present" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        create :create do
          description "Creates a new post."
          accept [:title]
        end
      end
    end
    """

    assert [] = run_check(ActionMissingDescription, source)
  end

  test "reports multiple missing descriptions" do
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

    issues = run_check(ActionMissingDescription, source)
    assert [_, _] = issues
    assert issues |> Enum.map(& &1.line_no) |> Enum.sort() == [5, 9]
    assert Enum.all?(issues, &(&1.message =~ "description"))
  end

  test "no issue when inline description option is present" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        create :create, description: "Creates a post"
      end
    end
    """

    assert [] = run_check(ActionMissingDescription, source)
  end

  test "no issue for actions declared via defaults" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        defaults [:read, :destroy, create: :*, update: :*]
      end
    end
    """

    assert [] = run_check(ActionMissingDescription, source)
  end

  test "reports generic action without description, anchored at its line" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        action :send_newsletter, :ok do
          run MyApp.SendNewsletter
        end
      end
    end
    """

    assert [issue] = run_check(ActionMissingDescription, source)
    assert issue.trigger == "send_newsletter"
    assert issue.line_no == 5
    assert issue.message =~ "send_newsletter"
  end

  test "no issue for generic action with description" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        action :send_newsletter, :ok do
          description "Sends the weekly newsletter."
          run MyApp.SendNewsletter
        end
      end
    end
    """

    assert [] = run_check(ActionMissingDescription, source)
  end

  test "ignores non-Ash modules" do
    source = """
    defmodule MyApp.Utils do
      def hello, do: :world
    end
    """

    assert [] = run_check(ActionMissingDescription, source)
  end
end
