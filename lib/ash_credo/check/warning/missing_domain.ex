defmodule AshCredo.Check.Warning.MissingDomain do
  use Credo.Check,
    base_priority: :normal,
    category: :warning,
    tags: [:ash],
    explanations: [
      check: """
      In Ash 3.x, a resource normally declares its domain:

          use Ash.Resource, domain: MyApp.Blog

      Without it, code interfaces and domain configuration do not apply,
      and callers must supply the domain themselves. A resource shared
      across domains can opt out explicitly with `domain: nil` - the
      check accepts that and only flags a missing option.
      """
    ]

  alias AshCredo.Introspection
  alias AshCredo.Introspection.ResourceContext
  alias AshCredo.Orchestration

  @impl true
  def run(%SourceFile{} = source_file, params),
    do: Orchestration.flat_map_resource_context(source_file, params, &missing_domain_issues/2)

  defp missing_domain_issues(%ResourceContext{use_opts: opts} = context, issue_meta)
       when is_list(opts) do
    if Keyword.has_key?(opts, :domain) or Introspection.embedded_resource?(context) do
      []
    else
      [
        format_issue(issue_meta,
          message:
            "Resource declares no `domain:` in `use Ash.Resource`. " <>
              "Name its domain, or pass `domain: nil` explicitly if it is deliberately shared across domains.",
          trigger: "use Ash.Resource",
          line_no: Introspection.resource_issue_line(context)
        )
      ]
    end
  end

  defp missing_domain_issues(_context, _issue_meta), do: []
end
