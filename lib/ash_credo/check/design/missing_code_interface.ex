defmodule AshCredo.Check.Design.MissingCodeInterface do
  use Credo.Check,
    base_priority: :low,
    category: :design,
    tags: [:ash],
    explanations: [
      check: """
      Resources with actions but no `code_interface` section miss out on
      generated typed functions. Consider adding:

          code_interface do
            define :create
            define :read
          end
      """
    ]

  alias AshCredo.Introspection
  alias AshCredo.Orchestration

  @impl true
  def run(%SourceFile{} = source_file, params),
    do: Orchestration.flat_map_resource_context(source_file, params, &missing_code_interface_issues/2)

  defp missing_code_interface_issues(context, issue_meta) do
    actions_ast = Introspection.resource_section(context, :actions)
    has_code_interface = Introspection.resource_section(context, :code_interface) != nil

    if Introspection.actions_defined?(actions_ast) and not has_code_interface do
      [
        format_issue(issue_meta,
          message: "Resource has actions but no `code_interface` block.",
          trigger: "actions",
          line_no: Introspection.resource_issue_line(context, actions_ast)
        )
      ]
    else
      []
    end
  end
end
