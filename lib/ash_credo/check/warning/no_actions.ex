defmodule AshCredo.Check.Warning.NoActions do
  use Credo.Check,
    base_priority: :normal,
    category: :warning,
    tags: [:ash],
    explanations: [
      check: """
      A resource with a data layer but no actions defined cannot be
      interacted with through the Ash API. This is almost always an
      oversight.

      Add an `actions` block:

          actions do
            defaults [:read, :destroy, create: :*, update: :*]
          end
      """
    ]

  alias AshCredo.Introspection

  @impl true
  def run(%SourceFile{} = source_file, params) do
    if Introspection.ash_resource?(source_file) and Introspection.has_data_layer?(source_file) do
      actions_ast = Introspection.find_dsl_section(source_file, :actions)

      if Introspection.actions_defined?(actions_ast) do
        []
      else
        issue_meta = IssueMeta.for(source_file, params)

        line_no =
          Introspection.section_line(actions_ast) ||
            Introspection.find_use_line(source_file, [:Ash, :Resource]) || 1

        [
          format_issue(issue_meta,
            message: "Resource has a data layer but no actions defined.",
            trigger: "use Ash.Resource",
            line_no: line_no
          )
        ]
      end
    else
      []
    end
  end
end
