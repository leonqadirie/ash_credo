defmodule AshCredo.Check.Warning.NoActionsTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Warning.NoActions

  test "reports issue when resource has data layer but no actions" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, data_layer: AshPostgres.DataLayer

      attributes do
        uuid_primary_key :id
      end
    end
    """

    assert [issue] = run_check(NoActions, source)
    assert issue.message =~ "no actions defined"
  end

  test "reports issue when actions block is comment-only" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, data_layer: AshPostgres.DataLayer

      actions do
        # TODO: add actions
      end
    end
    """

    assert [issue] = run_check(NoActions, source)
    assert issue.message =~ "no actions defined"
  end

  test "no issue when actions are defined" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, data_layer: AshPostgres.DataLayer

      actions do
        defaults [:read]
      end
    end
    """

    assert [] = run_check(NoActions, source)
  end

  test "ignores resources without data layer" do
    source = """
    defmodule MyApp.Embedded do
      use Ash.Resource, domain: MyApp.Blog
    end
    """

    assert [] = run_check(NoActions, source)
  end

  test "ignores embedded resources" do
    source = """
    defmodule MyApp.Post.Metadata do
      use Ash.Resource, data_layer: :embedded
    end
    """

    assert [] = run_check(NoActions, source)
  end

  test "ignores non-Ash modules" do
    source = """
    defmodule MyApp.Utils do
      def hello, do: :world
    end
    """

    assert [] = run_check(NoActions, source)
  end
end
