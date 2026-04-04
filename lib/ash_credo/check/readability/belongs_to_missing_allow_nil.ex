defmodule AshCredo.Check.Readability.BelongsToMissingAllowNil do
  use Credo.Check,
    base_priority: :normal,
    category: :readability,
    tags: [:ash],
    explanations: [
      check: """
      A `belongs_to` without an explicit `allow_nil?` option relies on
      the framework default. Declaring it explicitly communicates intent
      and prevents surprises when defaults change.

          belongs_to :author, MyApp.Author, allow_nil?: false
      """
    ]

  alias AshCredo.Introspection

  @impl true
  def run(%SourceFile{} = source_file, params) do
    if Introspection.ash_resource?(source_file) do
      rels_ast = Introspection.find_dsl_section(source_file, :relationships)
      check_belongs_to(rels_ast, source_file, params)
    else
      []
    end
  end

  defp check_belongs_to(nil, _source_file, _params), do: []

  defp check_belongs_to(rels_ast, source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    rels_ast
    |> Introspection.entities(:belongs_to)
    |> Enum.reject(&has_allow_nil_opt?/1)
    |> Enum.map(fn {_, meta, [name | _]} ->
      format_issue(issue_meta,
        message: "`belongs_to :#{name}` is missing an explicit `allow_nil?` option.",
        trigger: "#{name}",
        line_no: meta[:line]
      )
    end)
  end

  defp has_allow_nil_opt?(entity_ast) do
    Introspection.entity_has_opt_key?(entity_ast, :allow_nil?)
  end
end
