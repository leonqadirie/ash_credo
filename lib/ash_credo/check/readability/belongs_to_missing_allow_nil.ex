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

      The check also scans `Spark.Dsl.Fragment` modules declared
      `of: Ash.Resource`.
      """
    ]

  alias AshCredo.Introspection
  alias AshCredo.Orchestration

  @impl true
  def run(%SourceFile{} = source_file, params),
    do:
      Orchestration.flat_map_resource_or_fragment_section(
        source_file,
        params,
        :relationships,
        &check_belongs_to/2
      )

  defp check_belongs_to(rels_ast, issue_meta) do
    rels_ast
    |> Introspection.entities(:belongs_to)
    |> Orchestration.missing_option_issues(:allow_nil?, issue_meta, __MODULE__)
  end
end
