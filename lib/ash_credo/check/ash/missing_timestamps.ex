defmodule AshCredo.Check.Ash.MissingTimestamps do
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

  alias AshCredo.Check.Helpers

  @impl true
  def run(%SourceFile{} = source_file, params) do
    if Helpers.ash_resource?(source_file) and Helpers.has_data_layer?(source_file) do
      attrs_ast = Helpers.find_dsl_section(source_file, :attributes)
      check_for_timestamps(attrs_ast, source_file, params)
    else
      []
    end
  end

  defp check_for_timestamps(nil, source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    [
      format_issue(issue_meta,
        message: "Resource is missing timestamps.",
        trigger: "attributes",
        line_no: Helpers.find_use_line(source_file, [:Ash, :Resource]) || 1
      )
    ]
  end

  defp check_for_timestamps(attrs_ast, source_file, params) do
    has_timestamps = Helpers.has_entity?(attrs_ast, :timestamps)

    has_manual_timestamps =
      Helpers.has_entity?(attrs_ast, :create_timestamp) and
        Helpers.has_entity?(attrs_ast, :update_timestamp)

    if has_timestamps or has_manual_timestamps do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)

      [
        format_issue(issue_meta,
          message: "Resource is missing timestamps.",
          trigger: "attributes",
          line_no: Helpers.section_line(attrs_ast)
        )
      ]
    end
  end
end
