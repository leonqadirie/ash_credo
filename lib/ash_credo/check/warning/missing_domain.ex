defmodule AshCredo.Check.Warning.MissingDomain do
  use Credo.Check,
    base_priority: :normal,
    category: :warning,
    tags: [:ash],
    explanations: [
      check: """
      In Ash 3.x, resources without a `domain:` option cannot be queried
      through the standard API.

          use Ash.Resource, domain: MyApp.Blog
      """
    ]

  alias AshCredo.Introspection

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Introspection.resource_modules()
    |> Enum.flat_map(&missing_domain_issues(&1, issue_meta))
  end

  defp missing_domain_issues(module_ast, issue_meta) do
    case Introspection.use_opts(module_ast, [:Ash, :Resource]) do
      opts when is_list(opts) ->
        if Keyword.has_key?(opts, :domain) or Introspection.embedded_resource?(module_ast) do
          []
        else
          [
            format_issue(issue_meta,
              message: "Resource is missing a `domain:` option in `use Ash.Resource`.",
              trigger: "use Ash.Resource",
              line_no: Introspection.find_use_line(module_ast, [:Ash, :Resource])
            )
          ]
        end

      _ ->
        []
    end
  end
end
