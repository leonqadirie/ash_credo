defmodule AshCredo.Check.Refactor.LargeResource do
  use Credo.Check,
    base_priority: :low,
    category: :refactor,
    tags: [:ash],
    param_defaults: [max_lines: 400],
    explanations: [
      check: """
      Large resource files are hard to navigate. Consider splitting
      with `Spark.Dsl.Fragment` or extracting changes/validations
      into separate modules.
      """,
      params: [
        max_lines: "Maximum line count before triggering this check."
      ]
    ]

  alias AshCredo.Introspection

  @impl true
  def run(%SourceFile{} = source_file, params) do
    max = Params.get(params, :max_lines, __MODULE__)
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Introspection.resource_modules()
    |> Enum.flat_map(&resource_size_issues(&1, max, issue_meta))
  end

  defp resource_size_issues(module_ast, max, issue_meta) do
    case Introspection.module_line_count(module_ast) do
      line_count when is_integer(line_count) and line_count > max ->
        [
          format_issue(issue_meta,
            message:
              "Resource is #{line_count} lines (limit: #{max}). Consider splitting with fragments.",
            trigger: "#{line_count} lines",
            line_no: Introspection.find_use_line(module_ast, [:Ash, :Resource]) || 1
          )
        ]

      _ ->
        []
    end
  end
end
