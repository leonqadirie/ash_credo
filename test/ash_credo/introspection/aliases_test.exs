defmodule AshCredo.Introspection.AliasesTest do
  @moduledoc """
  Direct unit tests for the Macro.Env-backed resolution helpers. These
  functions are exercised indirectly through the checks, but the long-tail
  fallback clauses (malformed directives, `:as` renames, grouped forms,
  `__MODULE__` targets, non-atom segments) are only reachable here without
  contriving exotic source. Every check that resolves a module reference
  depends on this module, so the fallbacks are worth pinning.
  """
  use ExUnit.Case, async: true

  alias AshCredo.Introspection.Aliases

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

  describe "resolved_module_ref/2" do
    test "returns non-ref, non-segment input unchanged" do
      assert Aliases.resolved_module_ref(123, %{env: Aliases.base_env()}) == 123
    end

    test "resolves segments against a context map carrying an env" do
      ctx = %{env: env_after(["alias Ash.Query, as: Q"])}

      assert Aliases.resolved_module_ref([:Q], ctx) == [:Ash, :Query]
    end

    test "resolves an __aliases__ node against a context map carrying an env" do
      ctx = %{env: env_after(["alias Ash.Query, as: Q"])}

      assert Aliases.resolved_module_ref({:__aliases__, [line: 3], [:Q]}, ctx) == [:Ash, :Query]
    end

    test "returns segments unchanged for an unrecognised context" do
      assert Aliases.resolved_module_ref([:Foo], :not_a_context) == [:Foo]
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
end
