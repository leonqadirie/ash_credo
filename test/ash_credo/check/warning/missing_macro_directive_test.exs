defmodule AshCredo.Check.Warning.MissingMacroDirectiveTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Warning.MissingMacroDirective
  alias AshCredo.Introspection.Compiled, as: CompiledIntrospection

  setup do
    CompiledIntrospection.clear_cache()
    :ok
  end

  describe "Ash.Query" do
    test "flags Ash.Query.filter without require" do
      source = """
      defmodule MyApp.PostQueries do
        def published do
          MyApp.Post
          |> Ash.Query.filter(state == :published)
          |> Ash.read!()
        end
      end
      """

      assert [issue] = run_check(MissingMacroDirective, source)
      assert issue.trigger == "Ash.Query.filter"
      assert issue.message =~ "require Ash.Query"
      assert issue.line_no == 4
    end

    test "no issue when require Ash.Query is at module top level" do
      source = """
      defmodule MyApp.PostQueries do
        require Ash.Query

        def published do
          MyApp.Post
          |> Ash.Query.filter(state == :published)
          |> Ash.read!()
        end
      end
      """

      assert [] = run_check(MissingMacroDirective, source)
    end

    test "no issue when import Ash.Query is at module top level" do
      source = """
      defmodule MyApp.PostQueries do
        import Ash.Query

        def published do
          Ash.Query.filter(MyApp.Post, state == :published)
        end
      end
      """

      assert [] = run_check(MissingMacroDirective, source)
    end

    test "import with :only still satisfies the check" do
      source = """
      defmodule MyApp.PostQueries do
        import Ash.Query, only: [filter: 2]

        def published do
          Ash.Query.filter(MyApp.Post, state == :published)
        end
      end
      """

      assert [] = run_check(MissingMacroDirective, source)
    end

    test "require inside the same function body satisfies the check (lexical scope)" do
      source = """
      defmodule MyApp.PostQueries do
        def published do
          require Ash.Query
          Ash.Query.filter(MyApp.Post, state == :published)
        end
      end
      """

      assert [] = run_check(MissingMacroDirective, source)
    end

    test "require inside an enclosing branch satisfies calls in that branch" do
      source = """
      defmodule MyApp.PostQueries do
        def published(true_branch?) do
          if true_branch? do
            require Ash.Query
            Ash.Query.filter(MyApp.Post, state == :published)
          else
            :noop
          end
        end
      end
      """

      assert [] = run_check(MissingMacroDirective, source)
    end

    test "require inside a `with` body satisfies calls there" do
      source = """
      defmodule MyApp.PostQueries do
        def published do
          with {:ok, _} <- {:ok, MyApp.Post} do
            require Ash.Query
            Ash.Query.filter(MyApp.Post, state == :published)
          end
        end
      end
      """

      assert [] = run_check(MissingMacroDirective, source)
    end

    test "require inside a `with` clause does NOT leak past the construct" do
      # Verified empirically: in Elixir, a `require` written inside a `with`
      # clause expression is scoped to the `with` and does not propagate to
      # code after the construct. The check matches that.
      source = """
      defmodule MyApp.PostQueries do
        def published do
          with _ <- (require Ash.Query; :ok) do
            :inside
          end

          # Outside the `with`, the require is no longer in scope.
          Ash.Query.filter(MyApp.Post, state == :published)
        end
      end
      """

      assert [issue] = run_check(MissingMacroDirective, source)
      assert issue.trigger == "Ash.Query.filter"
      assert issue.line_no == 8
    end

    test "require inside a `for` generator does NOT leak past the comprehension" do
      source = """
      defmodule MyApp.PostQueries do
        def published do
          for _ <- (require Ash.Query; [1]) do
            :inside
          end

          Ash.Query.filter(MyApp.Post, state == :published)
        end
      end
      """

      assert [issue] = run_check(MissingMacroDirective, source)
      assert issue.trigger == "Ash.Query.filter"
      assert issue.line_no == 7
    end

    test "require inside one branch does not leak into a sibling branch" do
      source = """
      defmodule MyApp.PostQueries do
        def published(use_first?) do
          if use_first? do
            require Ash.Query
            Ash.Query.filter(MyApp.Post, state == :published)
          else
            Ash.Query.filter(MyApp.Post, state == :draft)
          end
        end
      end
      """

      assert [issue] = run_check(MissingMacroDirective, source)
      assert issue.trigger == "Ash.Query.filter"
      # The `else` branch's call is the offending one.
      assert issue.line_no == 7
    end

    test "require inside a different function body does not reach this one" do
      source = """
      defmodule MyApp.PostQueries do
        def bar do
          require Ash.Query
          :ok
        end

        def published do
          Ash.Query.filter(MyApp.Post, state == :published)
        end
      end
      """

      assert [issue] = run_check(MissingMacroDirective, source)
      assert issue.line_no == 8
    end

    test "flags all Ash.Query macros when require is missing" do
      source = """
      defmodule MyApp.PostQueries do
        def a(q, x), do: Ash.Query.filter(q, x)
        def b(q, other), do: Ash.Query.equivalent_to(q, other)
        def c(q, other), do: Ash.Query.equivalent_to?(q, other)
        def d(q, other), do: Ash.Query.superset_of(q, other)
        def e(q, other), do: Ash.Query.superset_of?(q, other)
        def f(q, other), do: Ash.Query.subset_of(q, other)
        def g(q, other), do: Ash.Query.subset_of?(q, other)
      end
      """

      issues = run_check(MissingMacroDirective, source)
      triggers = issues |> Enum.map(& &1.trigger) |> Enum.sort()

      assert triggers == [
               "Ash.Query.equivalent_to",
               "Ash.Query.equivalent_to?",
               "Ash.Query.filter",
               "Ash.Query.subset_of",
               "Ash.Query.subset_of?",
               "Ash.Query.superset_of",
               "Ash.Query.superset_of?"
             ]
    end

    test "does NOT flag non-macro calls on Ash.Query (e.g. Ash.Query.new/1)" do
      source = """
      defmodule MyApp.PostQueries do
        def build, do: Ash.Query.new(MyApp.Post)
      end
      """

      assert [] = run_check(MissingMacroDirective, source)
    end

    test "multiple offending call sites emit one issue each with correct line numbers" do
      source = """
      defmodule MyApp.PostQueries do
        def published do
          Ash.Query.filter(MyApp.Post, state == :published)
        end

        def draft do
          Ash.Query.filter(MyApp.Post, state == :draft)
        end
      end
      """

      assert [first, second] = run_check(MissingMacroDirective, source)
      assert first.line_no == 3
      assert second.line_no == 7
      assert Enum.all?([first, second], &(&1.trigger == "Ash.Query.filter"))
    end
  end

  describe "Ash.Expr" do
    test "flags Ash.Expr.expr without require" do
      source = """
      defmodule MyApp.Calcs do
        def foo(x), do: Ash.Expr.expr(x)
      end
      """

      assert [issue] = run_check(MissingMacroDirective, source)
      assert issue.trigger == "Ash.Expr.expr"
      assert issue.message =~ "require Ash.Expr"
    end

    test "flags Ash.Expr.where / or_where / calc" do
      source = """
      defmodule MyApp.Calcs do
        def a(q), do: Ash.Expr.where(q, true)
        def b(q), do: Ash.Expr.or_where(q, true)
        def c, do: Ash.Expr.calc(1, type: :integer)
      end
      """

      issues = run_check(MissingMacroDirective, source)
      triggers = issues |> Enum.map(& &1.trigger) |> Enum.sort()
      assert triggers == ["Ash.Expr.calc", "Ash.Expr.or_where", "Ash.Expr.where"]
    end

    test "require Ash.Expr does NOT satisfy Ash.Query.filter (modules are independent)" do
      source = """
      defmodule MyApp.Mixed do
        require Ash.Expr

        def foo(q) do
          Ash.Query.filter(q, true)
        end
      end
      """

      assert [issue] = run_check(MissingMacroDirective, source)
      assert issue.trigger == "Ash.Query.filter"
    end

    test "only require Ash.Query → Ash.Expr calls still flagged" do
      source = """
      defmodule MyApp.Mixed do
        require Ash.Query

        def foo(q, x) do
          q
          |> Ash.Query.filter(x)
          |> Ash.Expr.expr(true)
        end
      end
      """

      assert [issue] = run_check(MissingMacroDirective, source)
      assert issue.trigger == "Ash.Expr.expr"
    end

    test "requiring both satisfies both" do
      source = """
      defmodule MyApp.Mixed do
        require Ash.Query
        require Ash.Expr

        def foo(q, x) do
          q
          |> Ash.Query.filter(x)
          |> Ash.Expr.expr(true)
        end
      end
      """

      assert [] = run_check(MissingMacroDirective, source)
    end
  end

  describe "scoping" do
    test "nested defmodule inherits outer require (matches Elixir)" do
      source = """
      defmodule MyApp.Outer do
        require Ash.Query

        defmodule Inner do
          def foo(q), do: Ash.Query.filter(q, true)
        end
      end
      """

      assert [] = run_check(MissingMacroDirective, source)
    end

    test "nested defmodule without an inherited require IS flagged" do
      source = """
      defmodule MyApp.Outer do
        defmodule Inner do
          def foo(q), do: Ash.Query.filter(q, true)
        end
      end
      """

      assert [issue] = run_check(MissingMacroDirective, source)
      assert issue.trigger == "Ash.Query.filter"
      assert issue.line_no == 3
    end

    test "nested defmodule with its own require is fine" do
      source = """
      defmodule MyApp.Outer do
        defmodule Inner do
          require Ash.Query
          def foo(q), do: Ash.Query.filter(q, true)
        end
      end
      """

      assert [] = run_check(MissingMacroDirective, source)
    end

    test "nested defmodule with a non-literal name is processed exactly once" do
      # Regression: with the LexicalScopeWalker migration, an early version
      # used `current_module_segments != nil` to detect nesting, which
      # returned nil for both "no enclosing module" and "in a module with a
      # non-literal name." That conflation meant the inner defmodule's calls
      # would be DOUBLE-processed - once as part of the outer module's pass
      # (because we wrongly thought we were still at outer-module scope) and
      # once in the inner's own pass. The walker exposes `in_module?/1` to
      # distinguish "no enclosing module" from "in an unknown-name module."
      source = """
      defmodule MyApp.Outer do
        defmodule Module.concat([:Generated, :Inner]) do
          def foo(q), do: Ash.Query.filter(q, true)
        end
      end
      """

      # Exactly ONE issue (not two). With the bug, the call would have
      # produced two identical issues - one per pass.
      assert [issue] = run_check(MissingMacroDirective, source)
      assert issue.trigger == "Ash.Query.filter"
      assert issue.line_no == 3
    end

    test "outer module call is not misattributed to inner module" do
      source = """
      defmodule MyApp.Outer do
        defmodule Inner do
          require Ash.Query
        end

        def foo(q), do: Ash.Query.filter(q, true)
      end
      """

      assert [issue] = run_check(MissingMacroDirective, source)
      assert issue.line_no == 6
    end

    test "calls inside quote do ... end are not flagged" do
      source = """
      defmodule MyApp.QueryMacros do
        defmacro build do
          quote do
            Ash.Query.filter(unquote(__MODULE__), true)
          end
        end
      end
      """

      assert [] = run_check(MissingMacroDirective, source)
    end

    test "call inside a resource DSL callback (fn inside change) is flagged when module-level require missing" do
      # A `change fn cs, _ -> ... end` block is inside an `actions do` block,
      # which is inside `use Ash.Resource`. There is no `def` wrapper - our
      # defmodule frame still applies, and the module needs `require Ash.Query`
      # at the top.
      source = """
      defmodule MyApp.Post do
        use Ash.Resource, domain: MyApp.Blog

        actions do
          update :publish do
            change fn cs, _ctx ->
              Ash.Query.filter(cs, true)
            end
          end
        end
      end
      """

      assert [issue] = run_check(MissingMacroDirective, source)
      assert issue.trigger == "Ash.Query.filter"
    end

    test "Ash resource DSL `filter expr(...)` (bare, local) is NOT flagged" do
      # The DSL `filter` / `expr` are unqualified local macro calls expanded
      # by Spark at resource-definition time - they are not qualified
      # `Ash.Query.filter(...)` / `Ash.Expr.expr(...)` calls and should never
      # be flagged by this check.
      source = """
      defmodule MyApp.Post do
        use Ash.Resource, domain: MyApp.Blog

        actions do
          read :published do
            filter expr(state == :published)
          end
        end
      end
      """

      assert [] = run_check(MissingMacroDirective, source)
    end
  end

  describe "configurable macro_modules (real fixture)" do
    # These tests use `AshCredoFixtures.FakeMacros`, a real compiled module in
    # `test/support/fixtures/ash_fixtures.ex`. It defines two macros
    # (`do_thing/1`, `other/2`) and one regular function (`regular/1`), so we
    # can verify the check's macro precision: regular functions on a
    # configured module must NOT be flagged.

    test "flags configured module's macros but NOT its regular functions" do
      source = """
      defmodule MyApp.Caller do
        def a, do: AshCredoFixtures.FakeMacros.do_thing(1)
        def b, do: AshCredoFixtures.FakeMacros.other(2, 3)
        def c, do: AshCredoFixtures.FakeMacros.regular(4)
      end
      """

      issues =
        run_check(MissingMacroDirective, source, macro_modules: [AshCredoFixtures.FakeMacros])

      triggers = issues |> Enum.map(& &1.trigger) |> Enum.sort()

      assert triggers == [
               "AshCredoFixtures.FakeMacros.do_thing",
               "AshCredoFixtures.FakeMacros.other"
             ]
    end

    test "user-supplied module is satisfied by its own require" do
      source = """
      defmodule MyApp.Caller do
        require AshCredoFixtures.FakeMacros
        def foo, do: AshCredoFixtures.FakeMacros.do_thing(1)
      end
      """

      assert [] =
               run_check(MissingMacroDirective, source,
                 macro_modules: [AshCredoFixtures.FakeMacros]
               )
    end

    test "dropping Ash.Expr from the list silences Ash.Expr calls" do
      source = """
      defmodule MyApp.Calcs do
        def foo(x), do: Ash.Expr.expr(x)
      end
      """

      assert [] = run_check(MissingMacroDirective, source, macro_modules: [Ash.Query])
    end
  end

  describe "aliased modules" do
    test "alias Ash.Query, as: Q + Q.filter is flagged when require is missing" do
      source = """
      defmodule MyApp.Caller do
        alias Ash.Query, as: Q

        def foo(q), do: Q.filter(q, true)
      end
      """

      assert [issue] = run_check(MissingMacroDirective, source)
      assert issue.trigger == "Ash.Query.filter"
      assert issue.line_no == 4
    end

    test "alias Ash.Query (default name) + Query.filter is flagged when require is missing" do
      source = """
      defmodule MyApp.Caller do
        alias Ash.Query

        def foo(q), do: Query.filter(q, true)
      end
      """

      assert [issue] = run_check(MissingMacroDirective, source)
      assert issue.trigger == "Ash.Query.filter"
    end

    test "alias + matching require under the alias name satisfies the check" do
      source = """
      defmodule MyApp.Caller do
        alias Ash.Query, as: Q
        require Q

        def foo(q), do: Q.filter(q, true)
      end
      """

      assert [] = run_check(MissingMacroDirective, source)
    end

    test "alias + matching require under the real name satisfies the check" do
      source = """
      defmodule MyApp.Caller do
        alias Ash.Query, as: Q
        require Ash.Query

        def foo(q), do: Q.filter(q, true)
      end
      """

      assert [] = run_check(MissingMacroDirective, source)
    end

    test "alias inside a function body is scoped to that function" do
      # `alias` inside `def foo` is visible to `Q.filter` inside the same body,
      # so the check should still flag it as needing `require Ash.Query`.
      source = """
      defmodule MyApp.Caller do
        def foo(q) do
          alias Ash.Query, as: Q
          Q.filter(q, true)
        end

        def bar(_q) do
          # `Q` is NOT in scope here, so `Q.filter` does not resolve to
          # `Ash.Query.filter` and is left alone.
          Q.filter(:noop)
        end
      end
      """

      issues = run_check(MissingMacroDirective, source)
      assert [issue] = issues
      assert issue.trigger == "Ash.Query.filter"
      assert issue.line_no == 4
    end

    test "defmodule inside `quote` is not analyzed as a real module" do
      # A `defmodule` inside a `quote` block belongs to the macro caller's
      # site - flagging anything inside it from the macro author's file would
      # be a false positive, exactly like the existing rule for direct calls
      # inside quote.
      source = """
      defmodule MyApp.GenMacro do
        defmacro build do
          quote do
            defmodule GeneratedMod do
              def foo(q), do: Ash.Query.filter(q, true)
            end
          end
        end
      end
      """

      assert [] = run_check(MissingMacroDirective, source)
    end

    test "outer module's alias is inherited into a nested defmodule" do
      # In Elixir, aliases declared in an enclosing module are visible inside
      # nested `defmodule` blocks. The check honors that, so the inner call
      # `Q.filter` resolves to `Ash.Query.filter` and is flagged for the
      # missing inner-module require.
      source = """
      defmodule MyApp.Outer do
        alias Ash.Query, as: Q

        defmodule Inner do
          def foo(q), do: Q.filter(q, true)
        end
      end
      """

      assert [issue] = run_check(MissingMacroDirective, source)
      assert issue.trigger == "Ash.Query.filter"
      assert issue.line_no == 5
    end

    test "outer alias inheritance does not cross-bleed between sibling nested modules" do
      # The alias is declared inside `defmodule First`, so it should NOT be
      # visible inside `defmodule Second` even though both are nested under
      # the same outer module.
      source = """
      defmodule MyApp.Outer do
        defmodule First do
          alias Ash.Query, as: Q

          def foo(q), do: Q.filter(q, true)
        end

        defmodule Second do
          # `Q` is not in scope here.
          def bar(_q), do: Q.filter(:noop)
        end
      end
      """

      issues = run_check(MissingMacroDirective, source)
      assert [issue] = issues
      assert issue.trigger == "Ash.Query.filter"
      assert issue.line_no == 5
    end

    test "grouped alias `alias Ash.{Query, Expr}` is honored" do
      source = """
      defmodule MyApp.Caller do
        alias Ash.{Query, Expr}

        def foo(q), do: Query.filter(q, true)
        def bar(x), do: Expr.expr(x)
      end
      """

      issues = run_check(MissingMacroDirective, source)
      triggers = issues |> Enum.map(& &1.trigger) |> Enum.sort()
      assert triggers == ["Ash.Expr.expr", "Ash.Query.filter"]
    end
  end

  describe "compile-dependent diagnostics" do
    test "emits a per-module not-loadable diagnostic for an unknown module and skips it" do
      source = """
      defmodule MyApp.Caller do
        def foo(x), do: Totally.Fake.Macros.do_thing(x)
        def bar(q), do: Ash.Query.filter(q, true)
      end
      """

      issues =
        run_check(MissingMacroDirective, source, macro_modules: [Totally.Fake.Macros, Ash.Query])

      # One diagnostic for the unloadable module...
      load_issue = find_by_message(issues, "Could not load")
      assert load_issue
      assert load_issue.message =~ "Totally.Fake.Macros"

      # ...and the Ash.Query.filter call is still flagged normally.
      assert find_by_trigger(issues, "Ash.Query.filter")

      # No spurious issue is emitted for the unresolved `Totally.Fake.Macros`
      # call sites - they're silently skipped when their module is dropped.
      refute find_by_trigger(issues, "Totally.Fake.Macros.do_thing")
    end
  end
end
