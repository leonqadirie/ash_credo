defmodule AshCredo.Check.Design.MissingTimestampsTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Design.MissingTimestamps
  alias AshCredo.Introspection.Compiled, as: CompiledIntrospection

  # Tests reference real fixture modules from `test/support/fixtures/ash_fixtures.ex`:
  #
  #   * `AshCredoFixtures.Blog.Post`    - has no timestamps (failure-path).
  #   * `AshCredoFixtures.Blog.Article` - uses `timestamps()` (happy-path).

  setup do
    CompiledIntrospection.clear_cache()
    :ok
  end

  # Note: the test source needs `data_layer:` set so the AST-level
  # `has_data_layer?/1` guard fires. The check then introspects the real
  # fixture module (e.g. `AshCredoFixtures.Blog.Post`) via
  # `Compiled.attributes/1` to see its actual attribute list.

  test "reports an issue when the resource has no timestamps" do
    source = """
    defmodule AshCredoFixtures.Blog.Post do
      use Ash.Resource,
        domain: AshCredoFixtures.Blog,
        data_layer: AshPostgres.DataLayer
    end
    """

    assert [issue] = run_check(MissingTimestamps, source)
    assert issue.message =~ "missing timestamps"
  end

  test "reports an issue when only `update_timestamp` is present" do
    # Regression: the UUID primary key (`:id`) is non-writable and has a
    # default function, which used to falsely satisfy the create-timestamp
    # predicate. The datetime-type filter fixes this, so this fixture -
    # which has only `update_timestamp :updated_at` - must now be flagged.
    source = """
    defmodule AshCredoFixtures.Blog.PartialTimestamps do
      use Ash.Resource,
        domain: AshCredoFixtures.Blog,
        data_layer: AshPostgres.DataLayer
    end
    """

    assert [issue] = run_check(MissingTimestamps, source)
    assert issue.message =~ "missing timestamps"
  end

  test "no issue when the resource uses `timestamps()`" do
    source = """
    defmodule AshCredoFixtures.Blog.Article do
      use Ash.Resource,
        domain: AshCredoFixtures.Blog,
        data_layer: AshPostgres.DataLayer
    end
    """

    assert [] = run_check(MissingTimestamps, source)
  end

  test "no issue when timestamps use a custom type (e.g. AshPostgres.TimestamptzUsec)" do
    source = """
    defmodule AshCredoFixtures.Blog.CustomTimestamps do
      use Ash.Resource,
        domain: AshCredoFixtures.Blog,
        data_layer: AshPostgres.DataLayer
    end
    """

    assert [] = run_check(MissingTimestamps, source)
  end

  test "ignores embedded resources (no data layer at the AST level)" do
    source = """
    defmodule AshCredoFixtures.Blog.SomeEmbedded do
      use Ash.Resource, data_layer: :embedded

      attributes do
        attribute :name, :string
      end
    end
    """

    assert [] = run_check(MissingTimestamps, source)
  end

  test "ignores non-Ash modules" do
    source = """
    defmodule MyApp.Utils do
      def hello, do: :world
    end
    """

    assert [] = run_check(MissingTimestamps, source)
  end

  test "emits a not-loadable config issue for an unknown resource" do
    source = """
    defmodule Totally.Fake.Resource do
      use Ash.Resource,
        domain: AshCredoFixtures.Blog,
        data_layer: AshPostgres.DataLayer
    end
    """

    assert [issue] = run_check(MissingTimestamps, source)
    assert issue.message =~ "Could not load"
    assert issue.message =~ "Totally.Fake.Resource"
  end
end
