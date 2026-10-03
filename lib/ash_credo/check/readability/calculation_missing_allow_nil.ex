defmodule AshCredo.Check.Readability.CalculationMissingAllowNil do
  use Credo.Check,
    base_priority: :normal,
    category: :readability,
    tags: [:ash],
    explanations: [
      check: """
      A `calculate` without an explicit `allow_nil?` option relies on the
      framework default of `true`. Ash does not infer the option from the
      calculation's expression or module. Generated client types (for
      example from AshTypescript) then mark every such calculation as
      nullable, even when it never returns nil.

      Declare the option explicitly, either inline or in the `do` block:

          calculate :progress, :float, expr(done_count / total_count),
            allow_nil?: false

          calculate :mine, :boolean, expr(author_id == ^actor(:id)) do
            allow_nil? true
          end

      Set `allow_nil? false` only when the calculation can never return
      nil. Ash does not enforce the declaration, so a wrong value makes
      generated client types promise a value the API can omit.

      The check also scans `Spark.Dsl.Fragment` modules declared
      `of: Ash.Resource`.

      The check reads the source because the compiled calculation stores
      `allow_nil?: true` whether the author wrote it or Ash defaulted it.
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
        :calculations,
        &check_calculations/2
      )

  defp check_calculations(calcs_ast, issue_meta) do
    calcs_ast
    |> Introspection.entities(:calculate)
    |> Orchestration.missing_option_issues(:allow_nil?, issue_meta, __MODULE__)
  end
end
