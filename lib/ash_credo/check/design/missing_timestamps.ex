defmodule AshCredo.Check.Design.MissingTimestamps do
  use Credo.Check,
    base_priority: :normal,
    category: :design,
    tags: [:ash],
    explanations: [
      check: """
      Ash resources backed by a data layer should include timestamps.
      Timestamps are essential for auditing, debugging, and cache invalidation.

      Add `timestamps()` inside your `attributes` block, or use
      `create_timestamp :inserted_at` and `update_timestamp :updated_at`.

      This check uses Ash's runtime introspection (`Ash.Resource.Info.attributes/1`)
      to detect timestamp attributes - including ones contributed by Spark
      transformers or extensions - rather than scanning the source AST. This
      means custom timestamp entity names are caught as long as they produce
      attributes with an auto-generated `default` (for create timestamps) or
      `update_default` (for update timestamps).

      ## Requirements

      Your project must be compiled before running `mix credo`. If Ash is
      not available in the VM running Credo, the check is a no-op and emits
      a single diagnostic.
      """
    ]

  # Ash is not a runtime dependency of ash_credo - users bring their own.
  # Suppress compile-time warnings; guarded at runtime by `with_compiled_check`.
  alias AshCredo.Introspection
  alias AshCredo.Introspection.Compiled, as: CompiledIntrospection

  @compile {:no_warn_undefined, [Ash.Type, Ash.Type.NewType]}

  @datetime_storage_types [
    :utc_datetime,
    :utc_datetime_usec,
    :naive_datetime,
    :naive_datetime_usec
  ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    CompiledIntrospection.with_compiled_check(
      fn ->
        format_issue(issue_meta,
          message:
            "Ash is not loaded in the VM running Credo - `MissingTimestamps` is a no-op. Add `:ash` as a dependency, or disable this check in `.credo.exs`.",
          line_no: 1
        )
      end,
      fn ->
        source_file
        |> Introspection.resource_contexts()
        |> Enum.flat_map(&check_resource(&1, issue_meta))
      end
    )
  end

  defp check_resource(%{absolute_segments: nil}, _issue_meta), do: []

  defp check_resource(context, issue_meta) do
    if Introspection.has_data_layer?(context) do
      check_loaded_resource(context, issue_meta)
    else
      []
    end
  end

  defp check_loaded_resource(
         %{absolute_segments: segments, module_ast: module_ast} = context,
         issue_meta
       ) do
    resource = Module.concat(segments)

    case CompiledIntrospection.attributes(resource) do
      {:ok, attributes} ->
        if has_timestamps?(attributes) do
          []
        else
          [missing_timestamps_issue(module_ast, context, issue_meta)]
        end

      {:error, :not_loadable} ->
        CompiledIntrospection.with_unique_not_loadable(resource, fn ->
          not_loadable_issue(resource, context, issue_meta)
        end)

      {:error, _} ->
        []
    end
  end

  # A resource has timestamps when it contains TWO DISTINCT datetime
  # attributes:
  #   * one matching the create_timestamp pattern (non-writable, default
  #     function, no update_default - so we don't count an update_timestamp
  #     as doubling for create), AND
  #   * one matching the update_timestamp pattern (non-writable,
  #     update_default function).
  #
  # This matches Ash's `timestamps()` macro and direct
  # `create_timestamp`/`update_timestamp` DSL entries without hard-coding
  # specific attribute names, while still catching partial setups where
  # only one side is present.
  defp has_timestamps?(attributes) do
    Enum.any?(attributes, &create_timestamp_attribute?/1) and
      Enum.any?(attributes, &update_timestamp_attribute?/1)
  end

  defp create_timestamp_attribute?(attribute) do
    Map.get(attribute, :writable?) == false and
      is_function(Map.get(attribute, :default)) and
      not is_function(Map.get(attribute, :update_default)) and
      datetime_attribute_type?(Map.get(attribute, :type))
  end

  defp update_timestamp_attribute?(attribute) do
    Map.get(attribute, :writable?) == false and
      is_function(Map.get(attribute, :update_default)) and
      datetime_attribute_type?(Map.get(attribute, :type))
  end

  # Restrict timestamp detection to datetime-typed attributes so that
  # PK attributes produced by e.g. `uuid_primary_key :id` - which are
  # also non-writable with a default function - don't satisfy the
  # create-timestamp predicate and mask a missing `create_timestamp`.
  #
  # Custom types like `AshPostgres.TimestamptzUsec` override `storage_type/1`
  # to return a DB-specific atom (e.g. `:"timestamptz(6)"`), so we cannot
  # rely on `Ash.Type.storage_type/2` alone. Instead we resolve through
  # `Ash.Type.NewType.subtype_of/1` to find the base Ash type and check
  # *its* storage type against the known datetime storage atoms.
  defp datetime_attribute_type?(type) when is_atom(type) and not is_nil(type) do
    type
    |> resolve_base_type()
    |> Ash.Type.storage_type([])
    |> Kernel.in(@datetime_storage_types)
  end

  defp datetime_attribute_type?(_), do: false

  defp resolve_base_type(type) do
    if Ash.Type.NewType.new_type?(type), do: Ash.Type.NewType.subtype_of(type), else: type
  end

  defp missing_timestamps_issue(module_ast, context, issue_meta) do
    attrs_ast = Introspection.find_dsl_section(module_ast, :attributes)

    format_issue(issue_meta,
      message: "Resource is missing timestamps.",
      trigger: "attributes",
      line_no: Introspection.resource_issue_line(context, attrs_ast)
    )
  end

  defp not_loadable_issue(resource, context, issue_meta) do
    format_issue(issue_meta,
      message:
        "Could not load `#{inspect(resource)}` for `MissingTimestamps`. Run `mix compile` before `mix credo`, or disable this check in `.credo.exs`.",
      line_no: Map.get(context, :use_line) || 1
    )
  end
end
