defmodule AshCredo.Introspection.AshCallSite do
  @moduledoc """
  A resolved Ash API call site discovered in source AST. Produced by
  `AshCredo.Introspection.AshCallResolver.sites/1` and consumed by the
  checks that flag or refine specific Ash call patterns
  (`AshCredo.Check.Refactor.UseCodeInterface`,
  `AshCredo.Check.Warning.UnknownAction`).

  Fields:

    * `:resolution` - lookup result for the called resource module:
      `{:ok, module, info_map}` when loaded, `{:not_loadable, module}` when
      unreachable, `:not_a_resource` for non-Ash modules, or `:ash_missing`
      when Ash itself is not loaded.
    * `:action_name` - atom of the action this call targets (literal `:action`
      keyword for `Ash.read/get/stream!`, positional arg for `bulk_*`/builders,
      or the resource's primary `:read` for the bare-form Ash.read! shape).
    * `:fun_name` - the function called (e.g. `:read!`, `:bulk_create`).
    * `:module` - alias-expanded segments of the called module.
    * `:arity` - arity of the call.
    * `:call_meta` - `Macro.t()` meta keyword list of the call (for `:line`).
    * `:call_info` - the original scanner `call_info` map; carries pipe
      origins, bindings, and enclosing module segments needed by downstream
      resolution.
    * `:builder_prefix` - `:changeset_to | :query_to | :input_to | nil` for
      the corresponding `for_*` builder shape, otherwise `nil`.
    * `:trace_record?` - resolver scratch: whether the first arg should be
      traced through bindings/pipes back to a literal resource. Internal to
      the resolver but kept on the site so the trace path is reentrant.
    * `:call_kind` - high-level call shape used to pick the right interface
      suggestion (`:read_many`, `:get_one`, `:stream_many`, `:builder`,
      `:bulk`, or `nil`).
    * `:lookup_keys` - the list of attribute names a `get_one` call looks up
      by (from a literal map / kw arg, or the resource's single-key primary
      key); `nil` for non-`:get_one` calls.
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
    :trace_record?,
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
    :trace_record?,
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
          trace_record?: boolean(),
          call_kind: :read_many | :get_one | :stream_many | :builder | :bulk | nil,
          lookup_keys: [atom()] | nil
        }
end
