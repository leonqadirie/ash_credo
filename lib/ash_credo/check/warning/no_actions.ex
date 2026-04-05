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
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Introspection.resource_modules()
    |> Enum.flat_map(&no_action_issues(&1, issue_meta))
  end

  defp no_action_issues(module_ast, issue_meta) do
    context = Introspection.resource_context(module_ast)

    if Introspection.has_data_layer?(context) do
      actions_ast = Introspection.find_dsl_section(context, :actions)

      if Introspection.actions_defined?(actions_ast) do
        []
      else
        line_no =
          Introspection.section_line(actions_ast) ||
            context.use_line || 1

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
