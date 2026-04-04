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

  alias AshCredo.Check.Helpers

  @impl true
  def run(%SourceFile{} = source_file, params) do
    case Helpers.use_opts(source_file, [:Ash, :Resource]) do
      opts when is_list(opts) ->
        if Keyword.has_key?(opts, :domain) or Helpers.embedded_resource?(source_file) do
          []
        else
          issue_meta = IssueMeta.for(source_file, params)

          [
            format_issue(issue_meta,
              message: "Resource is missing a `domain:` option in `use Ash.Resource`.",
              trigger: "use Ash.Resource",
              line_no: Helpers.find_use_line(source_file, [:Ash, :Resource])
            )
          ]
        end

      _ ->
        []
    end
  end
end
