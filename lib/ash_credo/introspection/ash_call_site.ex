defmodule AshCredo.Introspection.AshCallSite do
  @moduledoc """
  A resolved Ash API call site discovered in the source AST. Produced by
  `AshCredo.Introspection.AshCallResolver.sites/1` and consumed by the
  checks that flag or refine specific Ash call patterns
  (`AshCredo.Check.Refactor.UseCodeInterface`,
  `AshCredo.Check.Warning.UnknownAction`).

  Fields:

    * `:resolution` - lookup result for the called resource module:
      `{:ok, module, info_map}` when the module is loaded,
      `{:not_loadable, module}` when it is unreachable,
      `:not_a_resource` for non-Ash modules, or `:ash_missing` when Ash
      itself is not loaded.
    * `:action_name` - atom of the action this call targets (the literal
      `:action` keyword for `Ash.read/get/read_one/read_first/stream!`,
      the positional arg for `bulk_*`/builders, or the resource's
      primary `:read` for the bare-form Ash.read! shape).
    * `:fun_name` - the function called (e.g. `:read!`,
      `:bulk_create`).
    * `:module` - alias-expanded segments of the called module.
    * `:arity` - arity of the call.
    * `:call_meta` - the `Macro.t()` meta keyword list of the call (for
      `:line`).
    * `:call_info` - the original scanner `call_info` map; it carries
      the pipe origins, bindings, and enclosing module segments that
      downstream resolution needs.
    * `:builder_prefix` - `:changeset_to | :query_to | :input_to | nil`
      for the corresponding `for_*` builder shape, otherwise `nil`.
    * `:call_kind` - the high-level call shape, used by checks to pick
      the right interface suggestion (`:read_many`, `:read_one`,
      `:read_first`, `:get_one`, `:stream_many`, `:builder`, `:bulk`,
      or `nil`).
    * `:lookup_keys` - the list of attribute names a `get_one` call
      looks up by (from a literal map / kw arg, or the resource's
      single-key primary key); `nil` for non-`:get_one` calls.
  """

  @enforce_keys [
    :resolution,
    :action_name,
    :fun_name,
    :module,
    :arity,
    :call_meta,
    :call_info,
    :builder_prefix,
    :call_kind,
    :lookup_keys
  ]
  defstruct [
    :resolution,
    :action_name,
    :fun_name,
    :module,
    :arity,
    :call_meta,
    :call_info,
    :builder_prefix,
    :call_kind,
    :lookup_keys
  ]

  @type resolution ::
          {:ok, module(), map()}
          | {:not_loadable, module()}
          | :not_a_resource
          | :ash_missing

  @type t :: %__MODULE__{
          resolution: resolution(),
          action_name: atom(),
          fun_name: atom(),
          module: [atom()],
          arity: non_neg_integer(),
          call_meta: keyword(),
          call_info: map(),
          builder_prefix: :changeset_to | :query_to | :input_to | nil,
          call_kind:
            :read_many
            | :read_one
            | :read_first
            | :get_one
            | :stream_many
            | :builder
            | :bulk
            | nil,
          lookup_keys: [atom()] | nil
        }
end
