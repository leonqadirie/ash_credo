defmodule AshCredo.Introspection.UseMetadata do
  @moduledoc """
  Location and options of a `use SomeModule, opts` statement found inside a
  `defmodule` body. Produced by `AshCredo.Introspection`'s `find_use/2`,
  returned as `nil` when no matching `use` statement is found.
  """

  @enforce_keys [:line, :opts]
  defstruct [:line, :opts]

  @type t :: %__MODULE__{
          line: pos_integer() | nil,
          opts: keyword()
        }
end
