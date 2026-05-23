defmodule AshCredo.Check.Warning.MissingPrimaryKeyTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Warning.MissingPrimaryKey
  alias AshCredo.Introspection.Compiled, as: CompiledIntrospection

  # Tests reference real fixture modules from
  # `test/support/fixtures/ash_fixtures.ex`. The source string only drives the
  # AST-level `has_data_layer?/1` gate and the reported line number; the check
  # introspects the REAL compiled fixture via `Compiled.primary_key/1`.

  setup do
    CompiledIntrospection.clear_cache()
    :ok
  end

  test "reports an issue when the resource has no primary key" do
    source = """
    defmodule AshCredoFixtures.NoPrimaryKey do
      use Ash.Resource,
        domain: AshCredoFixtures.Blog,
        data_layer: AshPostgres.DataLayer
    end
    """

    assert [issue] = run_check(MissingPrimaryKey, source)
    assert issue.message =~ "missing a primary key"
  end

  test "no issue with a primary key declared in the resource" do
    source = """
    defmodule AshCredoFixtures.Blog.Post do
      use Ash.Resource,
        domain: AshCredoFixtures.Blog,
        data_layer: AshPostgres.DataLayer
    end
    """

    assert [] = run_check(MissingPrimaryKey, source)
  end

  test "no issue when the primary key lives in a Spark.Dsl.Fragment" do
    # Regression for #133: the composite PK is assembled from `belongs_to`
    # relationships declared in a fragment module - invisible to AST scanning
    # but present in `Ash.Resource.Info.primary_key/1`.
    source = """
    defmodule AshCredoFixtures.Blog.PostTag do
      use Ash.Resource,
        domain: AshCredoFixtures.Blog,
        data_layer: AshPostgres.DataLayer,
        fragments: [AshCredoFixtures.Blog.PostTagFragment]
    end
    """

    assert [] = run_check(MissingPrimaryKey, source)
  end

  test "ignores resources without a data layer" do
    source = """
    defmodule AshCredoFixtures.NoPrimaryKey do
      use Ash.Resource, domain: AshCredoFixtures.Blog
    end
    """

    assert [] = run_check(MissingPrimaryKey, source)
  end

  test "ignores embedded resources" do
    source = """
    defmodule AshCredoFixtures.NoPrimaryKey do
      use Ash.Resource, data_layer: :embedded
    end
    """

    assert [] = run_check(MissingPrimaryKey, source)
  end

  test "ignores non-Ash modules" do
    source = """
    defmodule AshCredoFixtures.Plain do
      def hello, do: :world
    end
    """

    assert [] = run_check(MissingPrimaryKey, source)
  end

  test "ignores modules that declare a data layer but are not resources" do
    source = """
    defmodule AshCredoFixtures.Plain do
      use Ash.Resource, data_layer: AshPostgres.DataLayer
    end
    """

    assert [] = run_check(MissingPrimaryKey, source)
  end

  test "emits a single not-loadable diagnostic for a resource that cannot be loaded" do
    source = """
    defmodule AshCredoFixtures.DoesNotExist do
      use Ash.Resource,
        domain: AshCredoFixtures.Blog,
        data_layer: AshPostgres.DataLayer
    end
    """

    assert [issue] = run_check(MissingPrimaryKey, source)
    assert issue.message =~ "Could not load"
  end
end
