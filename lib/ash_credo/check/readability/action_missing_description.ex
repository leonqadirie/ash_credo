defmodule AshCredo.Check.Readability.ActionMissingDescription do
  use Credo.Check,
    base_priority: :low,
    category: :readability,
    tags: [:ash],
    explanations: [
      check: """
      Actions without a `description` produce less useful API documentation
      in AshGraphql and AshJsonApi. Add a description:

          create :register do
            description "Register a new user account."
            # ...
          end

      The check also scans `Spark.Dsl.Fragment` modules declared
      `of: Ash.Resource`.
      """
    ]

  alias AshCredo.Introspection
  alias AshCredo.Orchestration

  @action_types ~w(create read update destroy action)a

  @impl true
  def run(%SourceFile{} = source_file, params),
    do:
      Orchestration.flat_map_resource_or_fragment_section(
        source_file,
        params,
        :actions,
        &check_descriptions/2
      )

  defp check_descriptions(actions_ast, issue_meta) do
    actions_ast
    |> Introspection.action_entities(@action_types)
    |> Orchestration.missing_option_issues(
      :description,
      issue_meta,
      __MODULE__,
      &"Action `#{&1}` is missing a `description`."
    )
  end
end
