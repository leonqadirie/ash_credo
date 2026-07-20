defmodule AshCredo.Introspection.AshCallScannerTest do
  @moduledoc """
  Direct tests for the bare imported-call surface of the scanner. Remote
  call collection is exercised heavily through the checks; the import
  resolution paths (only/except selections, local-def shadowing, pipe
  arity, lexical scoping) are pinned here.
  """
  use AshCredo.CheckCase

  alias AshCredo.Introspection.AshCallScanner

  defp call_modules(source) do
    source
    |> source_file()
    |> AshCallScanner.calls_with_module()
    |> Enum.map(fn {_ast, expanded_module} -> expanded_module end)
  end

  describe "bare imported calls" do
    test "yields a bare call resolved through import Ash" do
      source = """
      defmodule M do
        import Ash

        def go(q), do: read!(q)
      end
      """

      assert call_modules(source) == [[:Ash]]
    end

    test "yields nothing for the same bare call without the import" do
      source = """
      defmodule M do
        def go(q), do: read!(q)
      end
      """

      assert call_modules(source) == []
    end

    test "honors only: and except: selections" do
      source = """
      defmodule M do
        import Ash.Query, only: [limit: 2]

        def go(q) do
          q
          |> limit(10)
          |> sort(:title)
        end
      end
      """

      assert call_modules(source) == [[:Ash, :Query]]
    end

    test "a local def shadows the import, even via forward reference" do
      source = """
      defmodule M do
        import Ash

        def go(q), do: read!(q)

        defp read!(q), do: q
      end
      """

      assert call_modules(source) == []
    end

    test "resolves piped bare calls at their effective arity" do
      source = """
      defmodule M do
        import Ash.Query

        def go(q), do: q |> limit(10)
      end
      """

      # limit/2 exists, limit/1 does not: only the pipe bonus resolves it.
      assert call_modules(source) == [[:Ash, :Query]]
      assert call_modules(String.replace(source, "q |> limit(10)", "limit(10)")) == []
    end

    test "resolves a parens-less piped bare call" do
      source = """
      defmodule M do
        import Ash

        def go(q), do: q |> read!
      end
      """

      assert call_modules(source) == [[:Ash]]
    end

    test "an import inside one def does not leak into a sibling def" do
      source = """
      defmodule M do
        def a(q) do
          import Ash
          read!(q)
        end

        def b(q), do: read!(q)
      end
      """

      assert call_modules(source) == [[:Ash]]
    end

    test "erlang-module imports never yield" do
      source = """
      defmodule M do
        import :math

        def go(x), do: sqrt(x)
      end
      """

      assert call_modules(source) == []
    end

    test "bare and remote calls interleave in source order" do
      source = """
      defmodule M do
        import Ash

        def go(q) do
          q = Ash.Query.limit(q, 1)
          read!(q)
        end
      end
      """

      assert call_modules(source) == [[:Ash, :Query], [:Ash]]
    end
  end

  describe "calls_with_context/1 for bare calls" do
    test "builds the context map with the piped subject prepended" do
      source = """
      defmodule M do
        import Ash

        def go(q), do: q |> read!(authorize?: false)
      end
      """

      assert [context] =
               source
               |> source_file()
               |> AshCallScanner.calls_with_context()

      assert context.expanded_module == [:Ash]
      assert [{:q, _, nil}, [authorize?: false]] = context.args
      assert context.enclosing_module_segments == [:M]
      assert {:read!, _, [[authorize?: false]]} = context.call_ast
    end
  end
end
