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
  alias AshCredo.Orchestration

  @impl true
  def run(%SourceFile{} = source_file, params),
    do: Orchestration.flat_map_resource_context(source_file, params, &missing_domain_issues/2)

  defp missing_domain_issues(context, issue_meta) do
    case context.use_opts do
      opts when is_list(opts) ->
        if Keyword.has_key?(opts, :domain) or Introspection.embedded_resource?(context) do
          []
        else
          [
            format_issue(issue_meta,
              message: "Resource is missing a `domain:` option in `use Ash.Resource`.",
              trigger: "use Ash.Resource",
              line_no: Introspection.resource_issue_line(context)
            )
          ]
        end

      _ ->
        []
    end
  end
end
