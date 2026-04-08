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
      """
    ]

  alias AshCredo.Introspection
  alias AshCredo.Orchestration

  @action_types ~w(create read update destroy action)a

  @impl true
  def run(%SourceFile{} = source_file, params),
    do:
      Orchestration.flat_map_resource_section(
        source_file,
        params,
        :actions,
        &check_descriptions/2
      )

  defp check_descriptions(nil, _issue_meta), do: []

  defp check_descriptions(actions_ast, issue_meta) do
    actions_ast
    |> Introspection.action_entities(@action_types)
    |> Enum.reject(&has_description?/1)
    |> Enum.map(fn {type, meta, _} = entity ->
      name = Introspection.entity_name(entity)

      format_issue(issue_meta,
        message: "Action `#{name || type}` is missing a `description`.",
        trigger: "#{name || type}",
        line_no: meta[:line]
      )
    end)
  end

  defp has_description?(entity_ast) do
    Introspection.entity_has_opt_key?(entity_ast, :description)
  end
end
