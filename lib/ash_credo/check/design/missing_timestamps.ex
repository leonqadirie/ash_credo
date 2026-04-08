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
      """
    ]

  alias AshCredo.Introspection
  alias AshCredo.Orchestration

  @impl true
  def run(%SourceFile{} = source_file, params),
    do: Orchestration.flat_map_resource_context(source_file, params, &check_for_timestamps/2)

  defp check_for_timestamps(context, issue_meta) do
    if Introspection.has_data_layer?(context) do
      attrs_ast = Introspection.resource_section(context, :attributes)

      if is_nil(attrs_ast) do
        [
          format_issue(issue_meta,
            message: "Resource is missing timestamps.",
            trigger: "attributes",
            line_no: Introspection.resource_issue_line(context)
          )
        ]
      else
        check_attrs_for_timestamps(context, attrs_ast, issue_meta)
      end
    else
      []
    end
  end

  defp check_attrs_for_timestamps(context, attrs_ast, issue_meta) do
    has_timestamps = Introspection.has_entity?(attrs_ast, :timestamps)

    has_manual_timestamps =
      Introspection.has_entity?(attrs_ast, :create_timestamp) and
        Introspection.has_entity?(attrs_ast, :update_timestamp)

    if has_timestamps or has_manual_timestamps do
      []
    else
      [
        format_issue(issue_meta,
          message: "Resource is missing timestamps.",
          trigger: "attributes",
          line_no: Introspection.resource_issue_line(context, attrs_ast)
        )
      ]
    end
  end
end
