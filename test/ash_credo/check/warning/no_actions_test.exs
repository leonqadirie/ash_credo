defmodule AshCredo.Check.Warning.NoActionsTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Warning.NoActions
  alias AshCredo.Introspection.Compiled, as: CompiledIntrospection

  # Tests reference real fixture modules from `test/support/fixtures/ash_fixtures.ex`:
  #
  #   * `AshCredoFixtures.Blog.Empty` — has a (default) data layer and **no
  #     actions block**. Failure-path fixture for the migration.
  #   * `AshCredoFixtures.Blog.Post`  — has actions via `defaults [...]` and
  #     explicit `read`/`update` entries. Happy-path fixture.
  #
  # Note: the test source needs `data_layer:` set so the AST-level
  # `has_data_layer?/1` guard fires before we ask compiled for the action list.

  setup do
    CompiledIntrospection.clear_cache()
    :ok
  end

  test "reports an issue when the resource has a data layer but no actions" do
    source = """
    defmodule AshCredoFixtures.Blog.Empty do
      use Ash.Resource,
        domain: AshCredoFixtures.Blog,
        data_layer: AshPostgres.DataLayer
    end
    """

    assert [issue] = run_check(NoActions, source)
    assert issue.message =~ "no actions defined"
  end

  test "no issue when the resource has actions" do
    source = """
    defmodule AshCredoFixtures.Blog.Post do
      use Ash.Resource,
        domain: AshCredoFixtures.Blog,
        data_layer: AshPostgres.DataLayer
    end
    """

    assert [] = run_check(NoActions, source)
  end

  test "ignores resources without an explicit data_layer (AST gate)" do
    source = """
    defmodule AshCredoFixtures.Blog.Empty do
      use Ash.Resource, domain: AshCredoFixtures.Blog
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

  test "emits a not-loadable config issue for an unknown resource" do
    source = """
    defmodule Totally.Fake.Resource do
      use Ash.Resource,
        domain: AshCredoFixtures.Blog,
        data_layer: AshPostgres.DataLayer
    end
    """

    assert [issue] = run_check(NoActions, source)
    assert issue.message =~ "Could not load"
    assert issue.message =~ "Totally.Fake.Resource"
  end
end
