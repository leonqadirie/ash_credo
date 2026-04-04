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
    if Introspection.ash_resource?(source_file) do
      actions_ast = Introspection.find_dsl_section(source_file, :actions)
      has_code_interface = Introspection.find_dsl_section(source_file, :code_interface) != nil

      if Introspection.actions_defined?(actions_ast) and not has_code_interface do
        issue_meta = IssueMeta.for(source_file, params)

        [
          format_issue(issue_meta,
            message: "Resource has actions but no `code_interface` block.",
            trigger: "actions",
            line_no: 1
          )
        ]
      else
        []
      end
    else
      []
    end
  end
end
