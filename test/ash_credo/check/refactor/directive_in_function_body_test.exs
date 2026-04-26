defmodule AshCredo.Check.Refactor.DirectiveInFunctionBodyTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Refactor.DirectiveInFunctionBody

  describe "default `directive_modules: [Ash.Query]`" do
    test "flags `require Ash.Query` inside a public def body" do
      source = """
      defmodule MyApp.PostQueries do
        def published do
          require Ash.Query
          MyApp.Post |> Ash.Query.filter(Ash.Query.expr(state == :published))
        end
      end
      """

      assert [issue] = run_check(DirectiveInFunctionBody, source)
      assert issue.trigger == "Ash.Query"
      assert issue.message =~ "require Ash.Query"
      assert issue.message =~ "top of the module"
      assert issue.line_no == 3
    end

    test "flags `require Ash.Query` inside a private defp body" do
      source = """
      defmodule MyApp.PostQueries do
        defp filter_published(query) do
          require Ash.Query
          Ash.Query.filter(query, Ash.Query.expr(state == :published))
        end
      end
      """

      assert [issue] = run_check(DirectiveInFunctionBody, source)
      assert issue.trigger == "Ash.Query"
    end

    test "flags `import Ash.Query` inside a function body" do
      source = """
      defmodule MyApp.PostQueries do
        def published do
          import Ash.Query
          filter(MyApp.Post, expr(state == :published))
        end
      end
      """

      assert [issue] = run_check(DirectiveInFunctionBody, source)
      assert issue.message =~ "import Ash.Query"
    end

    test "flags `alias Ash.Query` inside a function body" do
      source = """
      defmodule MyApp.PostQueries do
        def published do
          alias Ash.Query
          Query.filter(MyApp.Post, Query.expr(state == :published))
        end
      end
      """

      assert [issue] = run_check(DirectiveInFunctionBody, source)
      assert issue.message =~ "alias Ash.Query"
    end

    test "no issue when `require Ash.Query` is at the top of the module" do
      source = """
      defmodule MyApp.PostQueries do
        require Ash.Query

        def published do
          MyApp.Post |> Ash.Query.filter(Ash.Query.expr(state == :published))
        end

        def draft do
          MyApp.Post |> Ash.Query.filter(Ash.Query.expr(state == :draft))
        end
      end
      """

      assert [] = run_check(DirectiveInFunctionBody, source)
    end

    test "no issue for `require Logger` inside a function (Logger isn't a target)" do
      source = """
      defmodule MyApp.Service do
        def call do
          require Logger
          Logger.info("hello")
        end
      end
      """

      assert [] = run_check(DirectiveInFunctionBody, source)
    end

    test "multiple offending directives in different functions emit one issue per directive" do
      source = """
      defmodule MyApp.PostQueries do
        def published do
          require Ash.Query
          MyApp.Post |> Ash.Query.filter(Ash.Query.expr(state == :published))
        end

        def draft do
          require Ash.Query
          MyApp.Post |> Ash.Query.filter(Ash.Query.expr(state == :draft))
        end

        def archived do
          require Ash.Query
          MyApp.Post |> Ash.Query.filter(Ash.Query.expr(state == :archived))
        end
      end
      """

      assert issues = run_check(DirectiveInFunctionBody, source)
      assert length(issues) == 3
      assert Enum.all?(issues, &(&1.trigger == "Ash.Query"))
    end

    test "flags `require Ash.Expr` inside a function body (included in default)" do
      source = """
      defmodule MyApp.PostQueries do
        def published do
          require Ash.Expr
          Ash.Expr.expr(state == :published)
        end
      end
      """

      assert [issue] = run_check(DirectiveInFunctionBody, source)
      assert issue.trigger == "Ash.Expr"
      assert issue.message =~ "require Ash.Expr"
    end

    test "does not flag `require Ash.Query.SomeChild` (different module)" do
      source = """
      defmodule MyApp.PostQueries do
        def published do
          require Ash.Query.Aggregation
          Ash.Query.Aggregation.do_thing()
        end
      end
      """

      assert [] = run_check(DirectiveInFunctionBody, source)
    end

    test "flags `require Ash.Query` in short-form `def foo, do: ...`" do
      source = """
      defmodule MyApp.PostQueries do
        def published, do: (require Ash.Query; Ash.Query.expr(state == :published))
      end
      """

      assert [issue] = run_check(DirectiveInFunctionBody, source)
      assert issue.trigger == "Ash.Query"
    end

    test "flags `require Ash.Query` inside a `defmacro` body" do
      source = """
      defmodule MyApp.QueryMacros do
        defmacro published_filter do
          require Ash.Query
          :ok
        end
      end
      """

      assert [issue] = run_check(DirectiveInFunctionBody, source)
      assert issue.trigger == "Ash.Query"
    end

    test "does NOT flag `require Ash.Query` inside `quote do ... end` (macro author injects to caller)" do
      source = """
      defmodule MyApp.QueryMacros do
        defmacro published_filter do
          quote do
            require Ash.Query
            Ash.Query.expr(state == :published)
          end
        end
      end
      """

      assert [] = run_check(DirectiveInFunctionBody, source)
    end

    test "with both top-level and in-function `require Ash.Query`, only the in-function one fires" do
      source = """
      defmodule MyApp.PostQueries do
        require Ash.Query

        def published do
          require Ash.Query
          MyApp.Post |> Ash.Query.filter(Ash.Query.expr(state == :published))
        end
      end
      """

      assert [issue] = run_check(DirectiveInFunctionBody, source)
      assert issue.line_no == 5
    end

    test "no issue for directive at top of a nested defmodule inside a function body" do
      source = """
      defmodule Outer do
        def build do
          defmodule Inner do
            require Ash.Query
            def run, do: :ok
          end
        end
      end
      """

      assert [] = run_check(DirectiveInFunctionBody, source)
    end

    test "still flags directive inside a def inside a nested defmodule" do
      source = """
      defmodule Outer do
        def build do
          defmodule Inner do
            def run do
              require Ash.Query
              :ok
            end
          end
        end
      end
      """

      assert [issue] = run_check(DirectiveInFunctionBody, source)
      assert issue.trigger == "Ash.Query"
    end

    test "ignores non-Ash modules entirely" do
      source = """
      defmodule MyApp.Utils do
        def hello, do: :world
      end
      """

      assert [] = run_check(DirectiveInFunctionBody, source)
    end
  end

  describe "configurable `directive_modules`" do
    test "extending the list to include a custom module flags it too" do
      source = """
      defmodule MyApp.PostQueries do
        def published do
          require MyApp.CustomMacros
          MyApp.CustomMacros.do_thing()
        end
      end
      """

      assert [issue] =
               run_check(DirectiveInFunctionBody, source,
                 directive_modules: [Ash.Query, Ash.Expr, MyApp.CustomMacros]
               )

      assert issue.trigger == "MyApp.CustomMacros"
    end

    test "extended list still flags defaults alongside the new entries" do
      source = """
      defmodule MyApp.PostQueries do
        def published do
          require Ash.Query
          require MyApp.CustomMacros
          Ash.Query.filter(MyApp.Post, MyApp.CustomMacros.do_thing())
        end
      end
      """

      assert issues =
               run_check(DirectiveInFunctionBody, source,
                 directive_modules: [Ash.Query, Ash.Expr, MyApp.CustomMacros]
               )

      assert sorted_triggers(issues) == ["Ash.Query", "MyApp.CustomMacros"]
    end

    test "accepts non-Ash modules in the configured list (off-label but allowed)" do
      # The check is general - the Ash framing lives in the default and the
      # docstring, not in a hard validator. Users with a custom in-house
      # query/expression module can opt in.
      source = """
      defmodule MyApp.Service do
        def log do
          require Logger
          Logger.info("hello")
        end
      end
      """

      assert [issue] = run_check(DirectiveInFunctionBody, source, directive_modules: [Logger])
      assert issue.trigger == "Logger"
    end
  end
end
