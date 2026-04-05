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
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Introspection.domain_modules()
    |> Enum.flat_map(&empty_domain_issues(&1, issue_meta))
  end

  defp empty_domain_issues(module_ast, issue_meta) do
    resources_ast = Introspection.find_dsl_section(module_ast, :resources)

    cond do
      is_nil(resources_ast) ->
        [
          format_issue(issue_meta,
            message: "Domain has no `resources` block.",
            trigger: "use Ash.Domain",
            line_no: Introspection.find_use_line(module_ast, [:Ash, :Domain]) || 1
          )
        ]

      Introspection.section_body(resources_ast) == [] ->
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
  end
end
