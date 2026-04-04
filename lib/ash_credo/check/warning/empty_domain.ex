defmodule AshCredo.Check.Warning.EmptyDomain do
  use Credo.Check,
    base_priority: :normal,
    category: :warning,
    tags: [:ash],
    explanations: [
      check: """
      A domain module with no resources registered is likely incomplete.

          resources do
            resource MyApp.Post
            resource MyApp.Comment
          end
      """
    ]

  alias AshCredo.Introspection

  @impl true
  def run(%SourceFile{} = source_file, params) do
    if Introspection.ash_domain?(source_file) do
      resources_ast = Introspection.find_dsl_section(source_file, :resources)

      cond do
        is_nil(resources_ast) ->
          issue_meta = IssueMeta.for(source_file, params)

          [
            format_issue(issue_meta,
              message: "Domain has no `resources` block.",
              trigger: "use Ash.Domain",
              line_no: Introspection.find_use_line(source_file, [:Ash, :Domain]) || 1
            )
          ]

        Introspection.section_body(resources_ast) == [] ->
          issue_meta = IssueMeta.for(source_file, params)

          [
            format_issue(issue_meta,
              message: "Domain has an empty `resources` block.",
              trigger: "resources",
              line_no: Introspection.section_line(resources_ast)
            )
          ]

        true ->
          []
      end
    else
      []
    end
  end
end
