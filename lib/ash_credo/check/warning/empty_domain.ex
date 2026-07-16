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

      ## Limitations

      This check scans the source AST, so it only sees resources registered
      literally in the `resources` block. Resources contributed by Spark
      transformers, extensions, or `Spark.Dsl.Fragment` modules are
      invisible to it, so a domain whose resources come from such a source
      may be flagged as empty even though it is not.
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
    resources_asts = Introspection.find_dsl_sections(module_ast, :resources)
    use_line = Introspection.find_use_line(module_ast, [:Ash, :Domain])

    case resources_asts do
      [] ->
        [
          format_issue(issue_meta,
            message: "Domain has no `resources` block.",
            trigger: "use Ash.Domain",
            line_no: Introspection.section_issue_line(nil, use_line)
          )
        ]

      [first_resources_ast | _] ->
        if Introspection.section_has_entries?(resources_asts) do
          []
        else
          [
            format_issue(issue_meta,
              message: "Domain has an empty `resources` block.",
              trigger: "resources",
              line_no: Introspection.section_issue_line(first_resources_ast, use_line)
            )
          ]
        end
    end
  end
end
