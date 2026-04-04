defmodule AshCredo.Check.Refactor.LargeResource do
  use Credo.Check,
    base_priority: :low,
    category: :refactor,
    tags: [:ash],
    param_defaults: [max_lines: 300],
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
    if Introspection.ash_resource?(source_file) do
      max = Params.get(params, :max_lines, __MODULE__)
      line_count = source_file |> SourceFile.lines() |> length()

      if line_count > max do
        issue_meta = IssueMeta.for(source_file, params)

        [
          format_issue(issue_meta,
            message:
              "Resource is #{line_count} lines (limit: #{max}). Consider splitting with fragments.",
            trigger: "#{line_count} lines",
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
