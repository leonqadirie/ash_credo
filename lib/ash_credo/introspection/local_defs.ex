defmodule AshCredo.Introspection.LocalDefs do
  @moduledoc """
  Indexes the function-like definitions (`def`, `defp`, `defmacro`,
  `defmacrop`, `defguard`, `defguardp`, `defdelegate`) of every
  `defmodule` in a source AST, keyed by the literal segment path of the
  enclosing modules (see `path_key/1`).

  Exists to keep import resolution honest: a bare call whose name/arity
  is defined in the enclosing module is a local call - locals shadow
  imports, and a genuine local/import conflict does not even compile -
  so it must never be attributed to an imported module. The index is a
  separate pre-pass because Elixir allows forward references: a bare
  call may target a local defined later in the module than the call.

  Deliberately conservative in the shadow direction: definitions inside
  `quote do ... end` blocks and heads with default arguments count for
  every arity they could produce. Over-counting suppresses an import
  attribution (a false negative for a consuming check); under-counting
  would fabricate one.
  """

  alias AshCredo.Introspection.Aliases

  @def_kinds ~w(def defp defmacro defmacrop defguard defguardp defdelegate)a

  @typedoc """
  Index key: concatenated literal `defmodule` segments of the enclosing
  module path (`[]` for top-level code, `nil` when any enclosing module
  has a non-literal name).
  """
  @type path_key :: [atom()] | nil

  @doc """
  Walks `ast` once and returns a map of `path_key` to the
  `MapSet.t({name, arity})` of definitions in that module.
  """
  @spec index(Macro.t()) :: %{optional(path_key()) => MapSet.t({atom(), arity()})}
  def index(ast) do
    {_ast, {index, _stack}} = Macro.traverse(ast, {%{}, []}, &enter/2, &leave/2)
    index
  end

  @doc """
  Builds the index key for a stack of literal defmodule segments,
  innermost first - the shape both this pre-pass and `AshCallScanner`'s
  traversal maintain, so their keys agree by construction. Any non-literal
  module name (`defmodule Module.concat(...)`) poisons the key to `nil`;
  all such modules share one bucket, which errs toward shadowing.
  """
  @spec path_key([[atom()] | nil]) :: path_key()
  def path_key(stack) do
    segments = Enum.reverse(stack)

    if !Enum.any?(segments, &is_nil/1) do
      List.flatten(segments)
    end
  end

  @doc "Returns `true` when `name/arity` is defined in the module at `key`."
  @spec local?(map(), path_key(), atom(), arity()) :: boolean()
  def local?(index, key, name, arity) do
    case index do
      %{^key => defs} -> MapSet.member?(defs, {name, arity})
      _ -> false
    end
  end

  defp enter({:defmodule, _, _} = node, {index, stack}) do
    {node, {index, [Aliases.defmodule_literal_segments(node) | stack]}}
  end

  defp enter({kind, _, [head | _]} = node, {index, stack}) when kind in @def_kinds do
    {node, {record(index, stack, def_head(head)), stack}}
  end

  defp enter(node, acc), do: {node, acc}

  defp leave({:defmodule, _, _} = node, {index, [_ | rest]}), do: {node, {index, rest}}
  defp leave(node, acc), do: {node, acc}

  # Head shapes: guards unwrap (`def foo(a) when ...`), a zero-arity head
  # without parens carries an atom context instead of a param list, and
  # each `\\` default widens the produced arity range downward. Dynamic
  # names (`def unquote(name)(...)`) yield nothing.
  defp def_head({:when, _, [inner | _]}), do: def_head(inner)

  defp def_head({name, _, params}) when is_atom(name) and is_list(params) do
    optional = Enum.count(params, &match?({:\\, _, _}, &1))
    total = length(params)
    {name, (total - optional)..total}
  end

  defp def_head({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: {name, 0..0}
  defp def_head(_head), do: nil

  defp record(index, _stack, nil), do: index

  defp record(index, stack, {name, arities}) do
    key = path_key(stack)
    entries = for arity <- arities, do: {name, arity}
    Map.update(index, key, MapSet.new(entries), &Enum.into(entries, &1))
  end
end
