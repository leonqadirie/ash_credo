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

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Introspection.resource_modules()
    |> Enum.flat_map(&missing_code_interface_issues(&1, issue_meta))
  end

  defp missing_code_interface_issues(module_ast, issue_meta) do
    context = Introspection.resource_context(module_ast)
    actions_ast = Introspection.find_dsl_section(context, :actions)
    has_code_interface = Introspection.find_dsl_section(context, :code_interface) != nil

    if Introspection.actions_defined?(actions_ast) and not has_code_interface do
      [
        format_issue(issue_meta,
          message: "Resource has actions but no `code_interface` block.",
          trigger: "actions",
          line_no:
            Introspection.section_line(actions_ast) ||
              context.use_line || 1
        )
      ]
    else
      []
    end
  end
end
