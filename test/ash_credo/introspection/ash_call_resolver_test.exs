defmodule AshCredo.Introspection.AshCallResolverTest do
  @moduledoc """
  Direct tests for the resolved-call-site pipeline. `UnknownAction` and
  `UseCodeInterface` exercise the common shapes, but the long-tail dispatch
  branches - literal lookup keys, the `for_*` builders, and the record/query
  provenance tracing - are only reachable by feeding the resolver the exact
  call shapes below. They all resolve against the loadable fixture
  `AshCredoFixtures.Blog.Post` (primary key `:id`, primary `:read` action).
  """
  use AshCredo.CheckCase

  alias AshCredo.Introspection.AshCallResolver
  alias AshCredo.Introspection.Compiled, as: CompiledIntrospection

  setup do
    CompiledIntrospection.clear_cache()
    :ok
  end

  defp sites(source), do: source |> source_file() |> AshCallResolver.sites()

  describe "get-by lookup keys" do
    test "extracts keys from a literal map id" do
      source = """
      defmodule M do
        def f, do: Ash.get!(AshCredoFixtures.Blog.Post, %{id: 1})
      end
      """

      assert [site] = sites(source)
      assert site.call_kind == :get_one
      assert site.lookup_keys == [:id]
    end

    test "extracts keys from a keyword id, ignoring :action" do
      source = """
      defmodule M do
        def f, do: Ash.get!(AshCredoFixtures.Blog.Post, action: :read, id: 1)
      end
      """

      assert [site] = sites(source)
      assert site.lookup_keys == [:id]
    end

    test "falls back to the resource's single primary key when the id is opaque" do
      source = """
      defmodule M do
        def f(id), do: Ash.get!(AshCredoFixtures.Blog.Post, id)
      end
      """

      assert [site] = sites(source)
      assert site.lookup_keys == [:id]
    end
  end

  describe "for_* builders" do
    test "tags an Ash.Query.for_read call as :query_to" do
      source = """
      defmodule M do
        def f, do: Ash.Query.for_read(AshCredoFixtures.Blog.Post, :read)
      end
      """

      assert [site] = sites(source)
      assert site.builder_prefix == :query_to
      assert site.call_kind == :builder
    end

    test "tags an Ash.ActionInput.for_action call as :input_to" do
      source = """
      defmodule M do
        def f, do: Ash.ActionInput.for_action(AshCredoFixtures.Blog.Post, :run)
      end
      """

      assert [site] = sites(source)
      assert site.builder_prefix == :input_to
    end
  end

  describe "provenance tracing" do
    test "traces a record-first for_update back through a get! binding" do
      source = """
      defmodule M do
        def f do
          post = Ash.get!(AshCredoFixtures.Blog.Post, 1)
          Ash.Changeset.for_update(post, :archive)
        end
      end
      """

      builder = Enum.find(sites(source), &(&1.builder_prefix == :changeset_to))

      assert match?({:ok, AshCredoFixtures.Blog.Post, _}, builder.resolution)
      assert builder.action_name == :archive
    end

    test "traces a bulk_update query origin through a pipe" do
      source = """
      defmodule M do
        def f do
          AshCredoFixtures.Blog.Post
          |> Ash.Query.for_read(:read)
          |> Ash.bulk_update(:archive, %{})
        end
      end
      """

      bulk = Enum.find(sites(source), &(&1.call_kind == :bulk))

      assert match?({:ok, AshCredoFixtures.Blog.Post, _}, bulk.resolution)
      assert bulk.action_name == :archive
    end
  end

  describe "resource segment resolution" do
    test "resolves __MODULE__ to the enclosing module" do
      source = """
      defmodule AshCredoFixtures.Blog.Post do
        def f, do: Ash.read!(__MODULE__)
      end
      """

      assert [site] = sites(source)
      assert match?({:ok, AshCredoFixtures.Blog.Post, _}, site.resolution)
    end

    test "emits no site for a bare read of a non-resource module" do
      source = """
      defmodule M do
        def f, do: Ash.read!(AshCredoFixtures.Plain)
      end
      """

      assert [] = sites(source)
    end
  end
end
