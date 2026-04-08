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
  alias AshCredo.Orchestration

  @impl true
  def run(%SourceFile{} = source_file, params),
    do: Orchestration.flat_map_resource_context(source_file, params, &no_action_issues/2)

  defp no_action_issues(context, issue_meta) do
    if Introspection.has_data_layer?(context) do
      actions_ast = Introspection.resource_section(context, :actions)

      if Introspection.actions_defined?(actions_ast) do
        []
      else
        [
          format_issue(issue_meta,
            message: "Resource has a data layer but no actions defined.",
            trigger: "use Ash.Resource",
            line_no: Introspection.resource_issue_line(context, actions_ast)
          )
        ]
      end
    else
      []
    end
  end
end
