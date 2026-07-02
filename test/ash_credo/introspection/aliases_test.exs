defmodule AshCredo.Introspection.AliasesTest do
  @moduledoc """
  Direct unit tests for the pure alias-resolution helpers. These functions are
  exercised indirectly through the checks, but the long-tail fallback clauses
  (non-list inputs, `:as` renames, grouped aliases, empty segments) are only
  reachable here without contriving exotic source. Every check that resolves a
  module reference depends on this module, so the fallbacks are worth pinning.
  """
  use ExUnit.Case, async: true

  alias AshCredo.Introspection.Aliases

  describe "module_aliases/2" do
    test "collects plain aliases from a module body" do
      assert Aliases.module_aliases(quoted("alias Ash.Query")) == [{[:Query], [:Ash, :Query]}]
    end

    test "collects require ... as: from a module body" do
      assert Aliases.module_aliases(quoted("require Ash.Query, as: Query")) ==
               [{[:Query], [:Ash, :Query]}]
    end

    test "ignores require without as:" do
      assert Aliases.module_aliases(quoted("require Ash.Query")) == []
    end

    test "returns [] for a non-defmodule AST" do
      assert Aliases.module_aliases({:def, [], []}) == []
      assert Aliases.module_aliases(:not_an_ast) == []
    end

    test "honours :before_line, dropping aliases that lack a usable line" do
      # The alias node is hand-built with empty meta, so `meta[:line]` is nil.
      # With a `:before_line` set, the nil line takes the non-integer fallback
      # in `alias_before?/2` and the alias is excluded.
      module =
        {:defmodule, [line: 1],
         [
           {:__aliases__, [line: 1], [:M]},
           [do: {:__block__, [], [{:alias, [], [{:__aliases__, [line: 2], [:Ash, :Query]}]}]}]
         ]}

      assert Aliases.module_aliases(module, before_line: 5) == []
    end
  end

  describe "expand_alias/2" do
    test "expands using the longest-matching alias mapping" do
      aliases = [{[:Q], [:Ash, :Query]}]
      assert Aliases.expand_alias([:Q, :Sub], aliases) == [:Ash, :Query, :Sub]
    end

    test "leaves segments untouched when an alias entry is not a pair" do
      assert Aliases.expand_alias([:Foo], [:not_a_pair]) == [:Foo]
    end

    test "returns segments unchanged when aliases is not a list" do
      assert Aliases.expand_alias([:Foo], nil) == [:Foo]
    end
  end

  describe "resolve_module_self/2" do
    test "substitutes __MODULE__ with the enclosing segments" do
      segments = [{:__MODULE__, [line: 2], nil}, :Post]

      assert Aliases.resolve_module_self(segments, [:MyApp, :Blog]) ==
               {:ok, [:MyApp, :Blog, :Post]}
    end

    test "passes through all-atom segments" do
      assert Aliases.resolve_module_self([:MyApp, :Post], [:MyApp]) == {:ok, [:MyApp, :Post]}
    end

    test "errors when __MODULE__ has no enclosing module to resolve against" do
      segments = [{:__MODULE__, [line: 2], nil}, :Post]
      assert Aliases.resolve_module_self(segments, nil) == :error
      assert Aliases.resolve_module_self(segments, []) == :error
    end

    test "errors when non-atom segments remain after substitution" do
      segments = [{:unquote, [line: 2], [:x]}, :Post]
      assert Aliases.resolve_module_self(segments, [:MyApp]) == :error
    end
  end

  describe "resolved_module_ref/3" do
    test "returns non-ref, non-segment input unchanged" do
      assert Aliases.resolved_module_ref(123, %{aliases: []}) == 123
    end

    test "resolves against a context map carrying module_ast and aliases" do
      ctx = %{module_ast: quoted("alias Ash.Query, as: Q"), aliases: [{[:Q], [:Ash, :Query]}]}
      assert Aliases.resolved_module_ref([:Q], ctx) == [:Ash, :Query]
    end

    test "resolves against a bare defmodule AST" do
      module_ast = quoted("alias Ash.Query, as: Q")
      assert Aliases.resolved_module_ref([:Q], module_ast) == [:Ash, :Query]
    end

    test "returns segments unchanged for an unrecognised context" do
      assert Aliases.resolved_module_ref([:Foo], :not_a_context) == [:Foo]
    end
  end

  describe "alias_entries/1" do
    test "maps a plain alias to its default (last-segment) name" do
      ast = {:alias, [], [{:__aliases__, [], [:Ash, :Query]}]}
      assert Aliases.alias_entries(ast) == [{[:Query], [:Ash, :Query]}]
    end

    test "uses the :as rename when present" do
      ast = {:alias, [], [{:__aliases__, [], [:Ash, :Query]}, [as: {:__aliases__, [], [:Q]}]]}
      assert Aliases.alias_entries(ast) == [{[:Q], [:Ash, :Query]}]
    end

    test "falls back to the default name when opts carry no usable :as" do
      ast = {:alias, [], [{:__aliases__, [], [:Ash, :Query]}, [warn: false]]}
      assert Aliases.alias_entries(ast) == [{[:Query], [:Ash, :Query]}]
    end

    test "expands a grouped alias" do
      ast = grouped_alias([:Ash], [[:Query], [:Changeset]])

      assert Aliases.alias_entries(ast) ==
               [{[:Query], [:Ash, :Query]}, {[:Changeset], [:Ash, :Changeset]}]
    end

    test "expands a grouped alias with a __MODULE__ prefix" do
      ast = Code.string_to_quoted!("alias __MODULE__.{Post, Comment}")

      assert [
               {[:Post], [{:__MODULE__, _, _}, :Post]},
               {[:Comment], [{:__MODULE__, _, _}, :Comment]}
             ] = Aliases.alias_entries(ast)
    end

    test "expands a grouped alias carrying trailing opts" do
      ast = grouped_alias([:Ash], [[:Query]], warn: false)
      assert Aliases.alias_entries(ast) == [{[:Query], [:Ash, :Query]}]
    end

    test "skips grouped suffixes that are not alias nodes" do
      ast =
        {:alias, [], [{{:., [], [{:__aliases__, [], [:Ash]}, :{}]}, [], [:not_an_alias_node]}]}

      assert Aliases.alias_entries(ast) == []
    end

    test "handles an empty target segment list" do
      ast = {:alias, [], [{:__aliases__, [], []}]}
      assert Aliases.alias_entries(ast) == [{[nil], []}]
    end

    test "maps require ... as: like the equivalent alias" do
      ast = Code.string_to_quoted!("require Ash.Query, as: Query")
      assert Aliases.alias_entries(ast) == [{[:Query], [:Ash, :Query]}]
    end

    test "returns [] for require without as: and for non-alias as: values" do
      assert Aliases.alias_entries(Code.string_to_quoted!("require Ash.Query")) == []
      assert Aliases.alias_entries(Code.string_to_quoted!("require Ash.Query, warn: false")) == []
    end

    test "returns [] for anything that is not an alias node" do
      assert Aliases.alias_entries(:garbage) == []
    end
  end

  describe "base_env/0" do
    test "starts with no aliases and Kernel pre-required, like any compilation unit" do
      env = Aliases.base_env()

      assert env.aliases == []
      assert Macro.Env.required?(env, Kernel)
      refute Macro.Env.required?(env, Ash.Query)
    end
  end

  describe "apply_directive/3" do
    test "records a plain alias under its default name" do
      env = env_after(["alias Ash.Query"])

      assert Aliases.expand_alias([:Query], env) == [:Ash, :Query]
    end

    test "records an as: rename, including trailing segments" do
      env = env_after(["alias Ash.Query, as: Q"])

      assert Aliases.expand_alias([:Q], env) == [:Ash, :Query]
      assert Aliases.expand_alias([:Q, :Sub], env) == [:Ash, :Query, :Sub]
    end

    test "records every suffix of a grouped alias, with and without opts" do
      env = env_after(["alias Ash.{Query, Changeset}"])

      assert Aliases.expand_alias([:Query], env) == [:Ash, :Query]
      assert Aliases.expand_alias([:Changeset], env) == [:Ash, :Changeset]

      env_with_opts = env_after(["alias Ash.{Query, Changeset}, warn: false"])

      assert Aliases.expand_alias([:Query], env_with_opts) == [:Ash, :Query]
    end

    test "require ... as: registers both the require and the alias" do
      env = env_after(["require Ash.Query, as: Q"])

      assert Macro.Env.required?(env, Ash.Query)
      assert Aliases.expand_alias([:Q], env) == [:Ash, :Query]
    end

    test "plain require registers the require but no alias" do
      env = env_after(["require Ash.Query"])

      assert Macro.Env.required?(env, Ash.Query)
      assert Aliases.expand_alias([:Query], env) == [:Query]
    end

    test "import registers a require, with or without only:" do
      assert Macro.Env.required?(env_after(["import Ash.Query"]), Ash.Query)

      assert Macro.Env.required?(
               env_after(["import Ash.Query, only: [filter: 2]"]),
               Ash.Query
             )
    end

    test "grouped require registers every suffix" do
      env = env_after(["require Ash.{Query, Expr}"])

      assert Macro.Env.required?(env, Ash.Query)
      assert Macro.Env.required?(env, Ash.Expr)
    end

    test "substitutes a leading __MODULE__ with the enclosing segments" do
      env = env_after(["alias __MODULE__.Post"], [:MyApp, :Blog])

      assert Aliases.expand_alias([:Post], env) == [:MyApp, :Blog, :Post]
    end

    test "substitutes __MODULE__ in grouped aliases" do
      env = env_after(["alias __MODULE__.{Post, Comment}"], [:MyApp, :Blog])

      assert Aliases.expand_alias([:Post], env) == [:MyApp, :Blog, :Post]
      assert Aliases.expand_alias([:Comment], env) == [:MyApp, :Blog, :Comment]
    end

    test "skips __MODULE__ targets when the enclosing module is unknown" do
      env = env_after(["alias __MODULE__.Post"], nil)

      assert Aliases.expand_alias([:Post], env) == [:Post]
    end

    test "expands alias chains at declaration time" do
      env = env_after(["alias Ash.Query, as: Q", "alias Q.Sub"])

      assert Aliases.expand_alias([:Sub], env) == [:Ash, :Query, :Sub]
    end

    test "a re-aliased name resolves to its newest target" do
      env = env_after(["alias Ash.Query, as: Q", "alias String, as: Q"])

      assert Aliases.expand_alias([:Q], env) == [:String]
    end

    test "skips entries with a multi-segment as: instead of guessing a name" do
      env = env_after(["alias Ash.Query, as: A.B"])

      assert env.aliases == []
    end

    test "falls back to the default name for a non-alias as: value" do
      env = env_after(["alias Ash.Query, as: :q"])

      assert Aliases.expand_alias([:Query], env) == [:Ash, :Query]
    end

    test "skips targets with non-atom segments" do
      env = env_after(["alias unquote(mod).Foo"])

      assert env.aliases == []
    end

    test "leaves the env unchanged for non-directive nodes" do
      env = Aliases.base_env()

      assert Aliases.apply_directive(env, {:def, [], []}, nil) == env
      assert Aliases.apply_directive(env, :not_an_ast, nil) == env
    end
  end

  describe "expand_to_module/2" do
    test "resolves through a recorded alias" do
      env = env_after(["alias Ash.Query, as: Q"])

      assert Aliases.expand_to_module([:Q], env) == {:ok, Ash.Query}
      assert Aliases.expand_to_module([:Q, :Sub], env) == {:ok, Ash.Query.Sub}
    end

    test "concatenates unaliased segments" do
      assert Aliases.expand_to_module([:MyApp, :Post], Aliases.base_env()) == {:ok, MyApp.Post}
    end

    test "returns :error for empty or non-atom segments" do
      env = Aliases.base_env()

      assert Aliases.expand_to_module([], env) == :error
      assert Aliases.expand_to_module([{:__MODULE__, [], nil}, :Post], env) == :error
      assert Aliases.expand_to_module(:not_segments, env) == :error
    end
  end

  describe "expand_alias/2 with a Macro.Env" do
    test "returns unmatched segments unchanged" do
      assert Aliases.expand_alias([:Unknown], Aliases.base_env()) == [:Unknown]
    end

    test "returns segments with non-atom members unchanged" do
      segments = [{:__MODULE__, [], nil}, :Post]

      assert Aliases.expand_alias(segments, Aliases.base_env()) == segments
    end
  end

  defp env_after(directive_sources, enclosing \\ nil) do
    Enum.reduce(directive_sources, Aliases.base_env(), fn src, env ->
      Aliases.apply_directive(env, Code.string_to_quoted!(src), enclosing)
    end)
  end

  defp quoted(src), do: Code.string_to_quoted!("defmodule M do\n#{src}\nend")

  defp grouped_alias(prefix, suffixes, opts \\ nil) do
    prefix_ast = {:__aliases__, [], prefix}
    suffix_asts = Enum.map(suffixes, &{:__aliases__, [], &1})
    group = {{:., [], [prefix_ast, :{}]}, [], suffix_asts}

    case opts do
      nil -> {:alias, [], [group]}
      opts -> {:alias, [], [group, opts]}
    end
  end
end
