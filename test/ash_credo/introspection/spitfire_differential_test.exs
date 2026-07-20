defmodule AshCredo.Introspection.SpitfireDifferentialTest do
  @moduledoc """
  Differential oracle: the `Macro.Env` our `LexicalScopeWalker` builds at
  a probe position versus the cursor env Spitfire's compiler-mirroring
  expansion computes for the same source. Both ultimately drive the same
  `Macro.Env` define/lookup APIs, so their alias tables and Ash import
  tables must agree; a divergence means one side models Elixir's lexical
  rules wrong.

  Spitfire arrives transitively through the optional `igniter` dep - it
  is guaranteed in this repo's dev/test environment but deliberately not
  a package dependency, so the suite skips (rather than fails) when
  Spitfire is absent. The corpus sticks to constructs both sides model:
  module bodies, def bodies, and import selections. Constructs where the
  walker is deliberately more capable are pinned by its own unit tests
  instead: per-clause `with`/`for` scoping, and grouped
  `alias Ash.{Changeset, ActionInput}` forms, which Spitfire's expansion
  does not register at all (verified empirically - it yields only the
  non-grouped aliases of the same body).
  """
  use ExUnit.Case, async: true

  alias AshCredo.Introspection.LexicalScopeWalker

  @probe "__cursor_probe__()"

  spitfire_available? = Code.ensure_loaded?(Spitfire) and Code.ensure_loaded?(Spitfire.Env)

  if !spitfire_available? do
    @moduletag :skip
  end

  test "module-body aliases and imports agree" do
    assert_envs_agree("""
    defmodule Differential.M do
      alias Ash.Query, as: Q
      alias Ash.Changeset
      import Ash.Query, only: [limit: 2]
      #{@probe}
    end
    """)
  end

  test "def-body imports agree" do
    assert_envs_agree("""
    defmodule Differential.M do
      def go(q) do
        import Ash
        #{@probe}
        q
      end
    end
    """)
  end

  test "plain imports with alias interplay agree" do
    assert_envs_agree("""
    defmodule Differential.M do
      import Ash.Expr
      alias Ash.Query
      #{@probe}
    end
    """)
  end

  test "a nested defmodule's implied alias agrees" do
    assert_envs_agree("""
    defmodule Differential.Outer do
      defmodule Inner do
        def x, do: :ok
      end

      import Ash
      #{@probe}
    end
    """)
  end

  defp assert_envs_agree(source) do
    ours = walker_env(source)
    theirs = spitfire_env(source)

    assert Enum.sort(ours.aliases) == Enum.sort(theirs.aliases)
    assert ash_imports(ours.functions) == ash_imports(theirs.functions)
    assert ash_imports(ours.macros) == ash_imports(theirs.macros)
  end

  # Projection to the Ash-namespaced import tables: base envs differ in
  # incidental Kernel bookkeeping, but every import this feature resolves
  # through must match exactly.
  defp ash_imports(module_funs) do
    for {module, funs} <- module_funs,
        String.starts_with?(Atom.to_string(module), "Elixir.Ash"),
        into: %{},
        do: {module, Enum.sort(funs)}
  end

  defp walker_env(source) do
    ast = Code.string_to_quoted!(source)

    {envs, _scope} =
      LexicalScopeWalker.traverse(
        ast,
        [],
        fn
          {:__cursor_probe__, _, []}, scope, acc -> [LexicalScopeWalker.env(scope) | acc]
          _node, _scope, acc -> acc
        end,
        fn _node, _scope, acc -> acc end
      )

    assert [env] = envs
    env
  end

  defp spitfire_env(source) do
    [prefix, _rest] = String.split(source, @probe, parts: 2)
    {:ok, ast} = Spitfire.container_cursor_to_quoted(prefix)
    {_ast, _state, _env, cursor_env} = Spitfire.Env.expand(ast, "nofile")
    cursor_env
  end
end
