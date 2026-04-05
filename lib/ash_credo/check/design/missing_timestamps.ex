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

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Introspection.resource_modules()
    |> Enum.flat_map(&check_for_timestamps(&1, issue_meta))
  end

  defp check_for_timestamps(module_ast, issue_meta) do
    if Introspection.has_data_layer?(module_ast) do
      attrs_ast = Introspection.find_dsl_section(module_ast, :attributes)

      if is_nil(attrs_ast) do
        [
          format_issue(issue_meta,
            message: "Resource is missing timestamps.",
            trigger: "attributes",
            line_no: Introspection.find_use_line(module_ast, [:Ash, :Resource]) || 1
          )
        ]
      else
        check_attrs_for_timestamps(attrs_ast, issue_meta)
      end
    else
      []
    end
  end

  defp check_attrs_for_timestamps(attrs_ast, issue_meta) do
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
          line_no: Introspection.section_line(attrs_ast)
        )
      ]
    end
  end
end
