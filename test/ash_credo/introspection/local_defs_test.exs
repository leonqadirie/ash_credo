defmodule AshCredo.Introspection.LocalDefsTest do
  @moduledoc """
  Pins the def-shape extraction and module-path keying of the shadow
  index. `AshCallScanner` consumes it for bare-call resolution; the
  head-shape long tail (guards, defaults, parens-less zero-arity,
  delegates, dynamic names) is only reachable directly.
  """
  use ExUnit.Case, async: true

  alias AshCredo.Introspection.LocalDefs

  defp index(source), do: source |> Code.string_to_quoted!() |> LocalDefs.index()

  test "indexes every def-like kind under the literal module path" do
    idx =
      index("""
      defmodule MyApp.M do
        def pub(a), do: a
        defp priv(a, b), do: {a, b}
        defmacro mac(a), do: a
        defmacrop macp(a), do: a
        defguard is_thing(x) when is_atom(x)
        defguardp is_other(x) when is_atom(x)
        defdelegate delegated(a, b), to: Enum, as: :at
      end
      """)

    assert idx == %{
             [:MyApp, :M] =>
               MapSet.new([
                 {:pub, 1},
                 {:priv, 2},
                 {:mac, 1},
                 {:macp, 1},
                 {:is_thing, 1},
                 {:is_other, 1},
                 {:delegated, 2}
               ])
           }
  end

  test "defaults widen the arity range downward" do
    idx =
      index("""
      defmodule M do
        def f(a, b \\\\ 1, c \\\\ 2), do: {a, b, c}
      end
      """)

    assert idx == %{[:M] => MapSet.new([{:f, 1}, {:f, 2}, {:f, 3}])}
  end

  test "handles guards and parens-less zero-arity heads" do
    idx =
      index("""
      defmodule M do
        def guarded(x) when is_integer(x), do: x
        def zero, do: :ok
      end
      """)

    assert idx == %{[:M] => MapSet.new([{:guarded, 1}, {:zero, 0}])}
  end

  test "keys nested modules by their concatenated literal path" do
    idx =
      index("""
      defmodule Outer do
        def outer_fun, do: :ok

        defmodule Inner.Deep do
          def inner_fun(a), do: a
        end
      end
      """)

    assert idx == %{
             [:Outer] => MapSet.new([{:outer_fun, 0}]),
             [:Outer, :Inner, :Deep] => MapSet.new([{:inner_fun, 1}])
           }
  end

  test "a non-literal module name poisons the key to nil" do
    idx =
      index("""
      defmodule Module.concat([:A, :B]) do
        def hidden(a), do: a
      end
      """)

    assert idx == %{nil => MapSet.new([{:hidden, 1}])}
  end

  test "skips dynamic def names" do
    idx =
      index("""
      defmodule M do
        def unquote(:gen)(a), do: a
        def static, do: :ok
      end
      """)

    assert idx == %{[:M] => MapSet.new([{:static, 0}])}
  end

  test "top-level script defs key on the empty path" do
    idx = index("def loose(a), do: a")

    assert idx == %{[] => MapSet.new([{:loose, 1}])}
  end

  test "local?/4 answers through the index" do
    idx = index("defmodule M do\n  def f(a), do: a\nend")

    assert LocalDefs.local?(idx, [:M], :f, 1)
    refute LocalDefs.local?(idx, [:M], :f, 2)
    refute LocalDefs.local?(idx, [:Other], :f, 1)
  end

  test "path_key/1 reverses the innermost-first stack and nil-poisons" do
    assert LocalDefs.path_key([]) == []
    assert LocalDefs.path_key([[:Inner], [:Outer]]) == [:Outer, :Inner]
    assert LocalDefs.path_key([[:Inner], nil]) == nil
  end
end
