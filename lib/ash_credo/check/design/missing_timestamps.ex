defmodule AshCredo.Check.Design.MissingTimestamps do
  use AshCredo.CompiledCheck,
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

  alias AshCredo.Introspection
  alias AshCredo.Introspection.Compiled, as: CompiledIntrospection
  alias AshCredo.Orchestration

  @impl AshCredo.CompiledCheck
  def run_compiled(source_file, params) do
    Orchestration.flat_map_loadable_resource(source_file, params, &check_resource_timestamps/3)
  end

  defp check_resource_timestamps(resource, context, issue_meta) do
    resource
    |> CompiledIntrospection.attributes()
    |> Orchestration.with_resource_info(
      resource,
      context,
      issue_meta,
      __MODULE__,
      fn attributes ->
        case timestamp_sides(attributes) do
          {true, true} ->
            []

          sides ->
            [missing_timestamps_issue(sides, context.module_ast, context, issue_meta)]
        end
      end
    )
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
  defp timestamp_sides(attributes) do
    Enum.reduce(attributes, {false, false}, fn attr, {has_create?, has_update?} ->
      {has_create? or create_timestamp_attribute?(attr),
       has_update? or update_timestamp_attribute?(attr)}
    end)
  end

  defp create_timestamp_attribute?(%{
         writable?: false,
         default: default,
         update_default: update_default,
         type: type
       }) do
    is_function(default) and not is_function(update_default) and datetime_attribute_type?(type)
  end

  defp create_timestamp_attribute?(_attribute), do: false

  defp update_timestamp_attribute?(%{
         writable?: false,
         update_default: update_default,
         type: type
       }) do
    is_function(update_default) and datetime_attribute_type?(type)
  end

  defp update_timestamp_attribute?(_attribute), do: false

  # Restrict timestamp detection to datetime-typed attributes so that
  # PK attributes produced by e.g. `uuid_primary_key :id` - which are
  # also non-writable with a default function - don't satisfy the
  # create-timestamp predicate and mask a missing `create_timestamp`.
  defp datetime_attribute_type?(type), do: CompiledIntrospection.datetime_type?(type)

  defp missing_timestamps_issue(sides, module_ast, context, issue_meta) do
    attrs_ast = Introspection.find_dsl_section(module_ast, :attributes)

    format_issue(issue_meta,
      message: missing_timestamps_message(sides),
      trigger: "attributes",
      line_no: Introspection.resource_issue_line(context, attrs_ast)
    )
  end

  defp missing_timestamps_message({false, false}) do
    "Resource has no timestamps. Add `timestamps()` to the `attributes` block."
  end

  defp missing_timestamps_message({false, true}) do
    "Resource has an update timestamp but no create timestamp. " <>
      "Add `create_timestamp :inserted_at` to the `attributes` block."
  end

  defp missing_timestamps_message({true, false}) do
    "Resource has a create timestamp but no update timestamp. " <>
      "Add `update_timestamp :updated_at` to the `attributes` block."
  end
end
