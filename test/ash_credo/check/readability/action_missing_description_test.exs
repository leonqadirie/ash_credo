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
    assert sorted_lines(issues) == [5, 9]
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

  test "reports issue in a resource fragment" do
    source = """
    defmodule MyApp.Post.Actions do
      use Spark.Dsl.Fragment, of: Ash.Resource

      actions do
        create :register
      end
    end
    """

    assert [issue] = run_check(ActionMissingDescription, source)
    assert issue.message == "Action `create :register` is missing a `description`."
    assert issue.line_no == 5
  end

  test "reports an action named by a module attribute with its source text" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      @action :publish

      actions do
        update @action
      end
    end
    """

    assert [issue] = run_check(ActionMissingDescription, source)
    assert issue.message == "Action `update @action` is missing a `description`."
    assert issue.trigger == "@action"
  end

  test "reports a generic action whose return type is a module attribute" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      @return_type :string

      actions do
        action :label, @return_type do
          run MyApp.Label
        end
      end
    end
    """

    assert [issue] = run_check(ActionMissingDescription, source)
    assert issue.trigger == "label"
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
