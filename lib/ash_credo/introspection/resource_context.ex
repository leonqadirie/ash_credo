defmodule AshCredo.Introspection.ResourceContext do
  @moduledoc """
  Shared metadata for an Ash resource module discovered in a source file.
  Produced by `AshCredo.Introspection.resource_contexts/1` and consumed by
  every Design.* check that needs positional information about the
  `defmodule` or its `use Ash.Resource` call.

  `:absolute_segments` is the full enclosing path of the resource's
  `defmodule` name (e.g. `[:MyApp, :Blog, :Post]`), or `nil` when the
  module name is not a literal alias.
  """

  @enforce_keys [:module_ast, :aliases, :use_line, :use_opts, :absolute_segments]
  defstruct [:module_ast, :aliases, :use_line, :use_opts, :absolute_segments]

  @type t :: %__MODULE__{
          module_ast: Macro.t(),
          aliases: [{[atom()], [atom()]}],
          use_line: pos_integer() | nil,
          use_opts: keyword(),
          absolute_segments: [atom()] | nil
        }
end
