defmodule AshCredo.Introspection.LexicalScopeWalkerTest do
  use ExUnit.Case, async: true

  alias AshCredo.Introspection.Aliases
  alias AshCredo.Introspection.LexicalScopeWalker
  alias AshCredo.Introspection.LexicalScopeWalker.Scope

  # Convenience: walk an AST and return only the final user_state (drop scope).
  defp walk(ast, user_state, on_enter, on_leave, opts \\ []) do
    {state, _scope} = LexicalScopeWalker.traverse(ast, user_state, on_enter, on_leave, opts)
    state
  end

  defp parse!(source), do: Code.string_to_quoted!(source)

  defp record_env_at(target_call) do
    fn
      {{:., _, [_, ^target_call]}, _, _}, scope, acc ->
        [LexicalScopeWalker.env(scope) | acc]

      _node, _scope, acc ->
        acc
    end
  end

  defp noop, do: fn _node, _scope, acc -> acc end

  defp resolves?(env, segments, target), do: Aliases.expand_alias(segments, env) == target

  describe "env frame push/pop" do
    test "alias declared in module body is visible at every nested call" do
      ast =
        parse!("""
        defmodule Foo do
          alias Ash.Query

          def go(q), do: Probe.mark(Query)
        end
        """)

      [env_at_mark] = walk(ast, [], record_env_at(:mark), noop())

      assert resolves?(env_at_mark, [:Query], [:Ash, :Query])
    end

    test "alias declared inside a def body is scoped to that def" do
      ast =
        parse!("""
        defmodule Foo do
          def first(q) do
            alias Ash.Query, as: Q
            Probe.mark(Q)
          end

          def second(q), do: Probe.mark(Q)
        end
        """)

      results =
        walk(ast, [], record_env_at(:mark), noop())
        |> Enum.reverse()

      assert [env_in_first, env_in_second] = results
      assert resolves?(env_in_first, [:Q], [:Ash, :Query])
      assert resolves?(env_in_second, [:Q], [:Q])
    end

    test "alias inside one branch does not leak into the sibling branch" do
      ast =
        parse!("""
        defmodule Foo do
          def go(flag) do
            if flag do
              alias Ash.Query, as: Q
              Probe.mark(Q)
            else
              Probe.mark(Q)
            end
          end
        end
        """)

      results =
        walk(ast, [], record_env_at(:mark), noop())
        |> Enum.reverse()

      [env_in_do, env_in_else] = results
      assert resolves?(env_in_do, [:Q], [:Ash, :Query])
      assert resolves?(env_in_else, [:Q], [:Q])
    end
  end

  describe "require and import tracking" do
    test "require in one def is not visible in a sibling def" do
      ast =
        parse!("""
        defmodule Foo do
          def first(q) do
            require Ash.Query
            Probe.mark(q)
          end

          def second(q), do: Probe.mark(q)
        end
        """)

      results =
        walk(ast, [], record_env_at(:mark), noop())
        |> Enum.reverse()

      [env_in_first, env_in_second] = results
      assert Macro.Env.required?(env_in_first, Ash.Query)
      refute Macro.Env.required?(env_in_second, Ash.Query)
    end

    test "require inside a with clause is visible in its do block but not after" do
      ast =
        parse!("""
        defmodule Foo do
          def go do
            with _x <- (require Ash.Query; :ok) do
              Probe.mark(:inside)
            end
            Probe.mark(:after)
          end
        end
        """)

      results =
        walk(ast, [], record_env_at(:mark), noop())
        |> Enum.reverse()

      [env_inside, env_after] = results
      assert Macro.Env.required?(env_inside, Ash.Query)
      refute Macro.Env.required?(env_after, Ash.Query)
    end

    test "import registers a require" do
      ast =
        parse!("""
        defmodule Foo do
          import Ash.Query

          def go(q), do: Probe.mark(q)
        end
        """)

      [env_at_mark] = walk(ast, [], record_env_at(:mark), noop())

      assert Macro.Env.required?(env_at_mark, Ash.Query)
    end
  end

  describe "quote handling" do
    test "aliases declared inside quote are dropped by default" do
      ast =
        parse!("""
        defmodule Foo do
          defmacro build do
            quote do
              alias Ash.Query, as: Q
              Probe.mark(Q)
            end
          end

          def go, do: Probe.mark(Q)
        end
        """)

      results =
        walk(ast, [], record_env_at(:mark), noop())
        |> Enum.reverse()

      [env_inside_quote, env_after_quote] = results
      # The Q alias was dropped, so it's NOT visible at either probe site.
      assert resolves?(env_inside_quote, [:Q], [:Q])
      assert resolves?(env_after_quote, [:Q], [:Q])
    end

    test "in_quote? reflects nesting" do
      ast =
        parse!("""
        defmodule Foo do
          defmacro build do
            quote do
              Probe.mark(:inside)
            end
          end

          def after_quote, do: Probe.mark(:outside)
        end
        """)

      flags =
        walk(
          ast,
          [],
          fn
            {{:., _, [_, :mark]}, _, _}, scope, acc ->
              [LexicalScopeWalker.in_quote?(scope) | acc]

            _node, _scope, acc ->
              acc
          end,
          noop()
        )
        |> Enum.reverse()

      assert flags == [true, false]
    end

    test "track_aliases_in_quote: true records aliases inside quote" do
      ast =
        parse!("""
        defmodule Foo do
          defmacro build do
            quote do
              alias Ash.Query, as: Q
              Probe.mark(Q)
            end
          end
        end
        """)

      [env_inside_quote] =
        walk(ast, [], record_env_at(:mark), noop(), track_aliases_in_quote: true)

      assert resolves?(env_inside_quote, [:Q], [:Ash, :Query])
    end
  end

  describe "lexical_scope_nodes opt" do
    test "with-construct scopes aliases by default (matches Elixir)" do
      # Verified empirically: a `require`/`alias` declared inside a `with`
      # clause does NOT propagate to expressions after the construct in
      # Elixir. The walker's default `lexical_scope_nodes: [:with, :for]`
      # mirrors that, so alias `Q` is gone after the with ends.
      ast =
        parse!("""
        defmodule Foo do
          def go do
            with _x <- (alias Ash.Query, as: Q; :ok) do
              :inside
            end
            Probe.mark(Q)
          end
        end
        """)

      [env_after_with] = walk(ast, [], record_env_at(:mark), noop())

      assert resolves?(env_after_with, [:Q], [:Q])
    end

    test "for-construct scopes aliases by default (matches Elixir)" do
      ast =
        parse!("""
        defmodule Foo do
          def go do
            for _ <- (alias Ash.Query, as: Q; [1]) do
              :inside
            end
            Probe.mark(Q)
          end
        end
        """)

      [env_after_for] = walk(ast, [], record_env_at(:mark), noop())

      assert resolves?(env_after_for, [:Q], [:Q])
    end

    test "passing lexical_scope_nodes: [] opts out of with/for scoping" do
      # Explicit empty list overrides the default - aliases inside with/for
      # then leak. Sensible only for callers with a specific need; verifies
      # the opt is actually wired through.
      ast =
        parse!("""
        defmodule Foo do
          def go do
            with _x <- (alias Ash.Query, as: Q; :ok) do
              :inside
            end
            Probe.mark(Q)
          end
        end
        """)

      [env_after_with] =
        walk(ast, [], record_env_at(:mark), noop(), lexical_scope_nodes: [])

      assert resolves?(env_after_with, [:Q], [:Ash, :Query])
    end
  end

  describe "module_stack" do
    test "current_module_segments returns absolute path across nested defmodules" do
      ast =
        parse!("""
        defmodule MyApp.Outer do
          defmodule Inner do
            def go, do: Probe.mark()
          end
        end
        """)

      [segs] =
        walk(
          ast,
          [],
          fn
            {{:., _, [_, :mark]}, _, _}, scope, acc ->
              [LexicalScopeWalker.current_module_segments(scope) | acc]

            _node, _scope, acc ->
              acc
          end,
          noop()
        )

      assert segs == [:MyApp, :Outer, :Inner]
    end

    test "in_module?/1 returns true even for non-literal defmodule names" do
      ast =
        parse!("""
        defmodule Module.concat([:Outer, :Inner]) do
          def go, do: Probe.mark()
        end
        """)

      [in_module] =
        walk(
          ast,
          [],
          fn
            {{:., _, [_, :mark]}, _, _}, scope, acc ->
              [LexicalScopeWalker.in_module?(scope) | acc]

            _node, _scope, acc ->
              acc
          end,
          noop()
        )

      assert in_module == true
    end

    test "current_module_segments returns nil for non-literal defmodule names" do
      # `in_module?/1` distinguishes "not in a module" from "in a module
      # with unknown name"; `current_module_segments/1` returns nil for
      # unknown names so callers that need the segments can branch.
      ast =
        parse!("""
        defmodule Module.concat([:Foo]) do
          def go, do: Probe.mark()
        end
        """)

      [segs] =
        walk(
          ast,
          [],
          fn
            {{:., _, [_, :mark]}, _, _}, scope, acc ->
              [LexicalScopeWalker.current_module_segments(scope) | acc]

            _node, _scope, acc ->
              acc
          end,
          noop()
        )

      assert segs == nil
    end

    test "top-level defmodule honours visible aliases on its name" do
      ast =
        parse!("""
        alias MyApp.Accounts.User

        defmodule User do
          def go, do: Probe.mark()
        end
        """)

      [segs] =
        walk(
          ast,
          [],
          fn
            {{:., _, [_, :mark]}, _, _}, scope, acc ->
              [LexicalScopeWalker.current_module_segments(scope) | acc]

            _node, _scope, acc ->
              acc
          end,
          noop()
        )

      assert segs == [:MyApp, :Accounts, :User]
    end

    test "alias __MODULE__ targets resolve against the enclosing module" do
      ast =
        parse!("""
        defmodule MyApp.Blog do
          alias __MODULE__.Post

          def go, do: Probe.mark(Post)
        end
        """)

      [env_at_mark] = walk(ast, [], record_env_at(:mark), noop())

      assert resolves?(env_at_mark, [:Post], [:MyApp, :Blog, :Post])
    end
  end

  describe "grouped aliases" do
    test "alias Ash.{Query, Expr} produces both entries" do
      ast =
        parse!("""
        defmodule Foo do
          alias Ash.{Query, Expr}

          def go do
            Probe.mark(Query)
            Probe.mark(Expr)
          end
        end
        """)

      results = walk(ast, [], record_env_at(:mark), noop())

      assert Enum.all?(results, fn env ->
               resolves?(env, [:Query], [:Ash, :Query]) and
                 resolves?(env, [:Expr], [:Ash, :Expr])
             end)
    end
  end

  describe "callback timing" do
    test "on_enter for an :alias node sees the alias already added" do
      ast = parse!("alias Ash.Query, as: Q")

      [env_seen] =
        walk(
          ast,
          [],
          fn
            {:alias, _, _}, scope, acc -> [LexicalScopeWalker.env(scope) | acc]
            _node, _scope, acc -> acc
          end,
          noop()
        )

      assert resolves?(env_seen, [:Q], [:Ash, :Query])
    end

    test "on_leave for a :do block sees the scope before it pops" do
      ast =
        parse!("""
        if true do
          alias Ash.Query, as: Q
        end
        """)

      [env_seen] =
        walk(
          ast,
          [],
          noop(),
          fn
            {:do, _}, scope, acc -> [LexicalScopeWalker.env(scope) | acc]
            _node, _scope, acc -> acc
          end
        )

      assert resolves?(env_seen, [:Q], [:Ash, :Query])
    end
  end

  describe "callbacks return only user_state" do
    test "user_state can be any term, walker doesn't enforce a shape" do
      ast = parse!("Probe.mark()")

      # The exact node count is an implementation detail of Macro.traverse;
      # what matters is that on_enter ran for every visited node and the
      # callback's return value threaded through unchanged.
      assert %{count: count} =
               walk(
                 ast,
                 %{count: 0},
                 fn _node, _scope, %{count: count} ->
                   %{count: count + 1}
                 end,
                 noop()
               )

      assert count > 0

      assert walk(ast, [], fn node, _scope, acc -> [node | acc] end, noop())
             |> length() > 0
    end

    test "Scope struct exposes correct accessors" do
      scope = %Scope{}
      assert %Macro.Env{} = LexicalScopeWalker.env(scope)
      assert LexicalScopeWalker.quote_depth(scope) == 0
      assert LexicalScopeWalker.in_quote?(scope) == false
      assert LexicalScopeWalker.current_module_segments(scope) == nil
      refute LexicalScopeWalker.in_module?(scope)
    end
  end
end
