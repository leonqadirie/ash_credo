defmodule AshCredo.Introspection.Block do
  @moduledoc false

  alias Credo.Code.Block

  @doc "Returns the flattened list of top-level statements inside a module body."
  def module_body({:defmodule, _, _} = module_ast), do: do_block_entries(module_ast)
  def module_body(_), do: []

  @doc "Returns the flattened list of statements inside any AST node's `do` block."
  def do_block_entries(ast) do
    case Block.do_block_for(ast) do
      {:ok, _body} -> Block.calls_in_do_block(ast)
      nil -> []
    end
  end
end
