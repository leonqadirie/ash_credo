defmodule AshCredo.Introspection.AshCallResolverTest do
  @moduledoc """
  Direct tests for the resolved-call-site pipeline. `UnknownAction` and
  `UseCodeInterface` exercise the common shapes, but the long-tail dispatch
  branches - literal lookup keys, the `for_*` builders, and the record/query
  provenance tracing - are only reachable by feeding the resolver the exact
  call shapes below. They all resolve against the loadable fixture
  `AshCredoFixtures.Blog.Post` (primary key `:id`, primary `:read` action).
  """
  use AshCredo.CheckCase, clear_cache: true

  alias AshCredo.Introspection.AshCallResolver

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

    test "treats :action in an Ash.get/2 keyword identifier as a lookup key" do
      source = """
      defmodule M do
        def f, do: Ash.get!(AshCredoFixtures.Accounts.Account, action: "activate")
      end
      """

      assert [site] = sites(source)
      assert site.action_name == :read
      assert site.lookup_keys == [:action]
    end

    test "reads :action from Ash.get/3 options, not from its keyword identifier" do
      source = """
      defmodule M do
        def f do
          Ash.get!(
            AshCredoFixtures.Accounts.Account,
            [action: "activate"],
            action: :missing
          )
        end
      end
      """

      assert [site] = sites(source)
      assert site.action_name == :missing
      assert site.lookup_keys == [:action]
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

  describe "single-record reads" do
    test "resolves read_one and read_first variants with distinct call kinds" do
      source = """
      defmodule M do
        def a, do: Ash.read_one(AshCredoFixtures.Blog.Post, action: :published)
        def b, do: Ash.read_one!(AshCredoFixtures.Blog.Post, action: :published)
        def c, do: Ash.read_first(AshCredoFixtures.Blog.Post, action: :published)
        def d, do: Ash.read_first!(AshCredoFixtures.Blog.Post, action: :published)
      end
      """

      assert Enum.map(sites(source), &{&1.fun_name, &1.call_kind, &1.action_name}) == [
               {:read_one, :read_one, :published},
               {:read_one!, :read_one, :published},
               {:read_first, :read_first, :published},
               {:read_first!, :read_first, :published}
             ]
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

    test "resolves through alias __MODULE__.X without crashing" do
      # Regression: the alias target carries the raw __MODULE__ AST tuple,
      # which used to reach Module.concat/1 and raise FunctionClauseError.
      source = """
      defmodule AshCredoFixtures.Blog do
        alias __MODULE__.Post

        def f, do: Ash.read!(Post, action: :read)
      end
      """

      assert [site] = sites(source)
      assert match?({:ok, AshCredoFixtures.Blog.Post, _}, site.resolution)
    end

    test "resolves through multi-alias __MODULE__.{X} without crashing" do
      # The grouped __MODULE__ prefix is substituted at declaration time by
      # Aliases.apply_directive/3, so `Post` expands straight to the
      # absolute module; the implicit nested-module fallback would
      # coincidentally find the same module here, but the alias path is
      # what this exercises.
      source = """
      defmodule AshCredoFixtures.Blog do
        alias __MODULE__.{Post}

        def f, do: Ash.Changeset.for_create(Post, :create)
      end
      """

      assert [site] = sites(source)
      assert match?({:ok, AshCredoFixtures.Blog.Post, _}, site.resolution)
    end
  end
end
