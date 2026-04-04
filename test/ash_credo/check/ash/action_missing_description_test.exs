defmodule AshCredo.Check.Ash.ActionMissingDescriptionTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Ash.ActionMissingDescription

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
    assert length(issues) == 2
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

  test "ignores non-Ash modules" do
    source = """
    defmodule MyApp.Utils do
      def hello, do: :world
    end
    """

    assert [] = run_check(ActionMissingDescription, source)
  end
end
