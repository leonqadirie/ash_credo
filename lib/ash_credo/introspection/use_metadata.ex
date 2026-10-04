defmodule AshCredo.Introspection.UseMetadata do
  @moduledoc """
  Location, options, and lexical environment of a `use SomeModule, opts`
  statement found inside a `defmodule` body. The environment resolves
  module references in options using the aliases visible at the statement.
  Produced by `AshCredo.Introspection`'s `find_use/2`, which returns `nil`
  when no matching `use` statement is found.
  """

  @enforce_keys [:line, :opts]
  defstruct [:line, :opts, :env]

  @type t :: %__MODULE__{
          line: pos_integer() | nil,
          opts: keyword(),
          env: Macro.Env.t() | nil
        }
end
