defmodule AshCredo.Check.Ash.ActionMissingDescription do
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

  alias AshCredo.Check.Helpers

  @action_types ~w(create read update destroy action)a

  @impl true
  def run(%SourceFile{} = source_file, params) do
    if Helpers.ash_resource?(source_file) do
      actions_ast = Helpers.find_dsl_section(source_file, :actions)
      check_descriptions(actions_ast, source_file, params)
    else
      []
    end
  end

  defp check_descriptions(nil, _source_file, _params), do: []

  defp check_descriptions(actions_ast, source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    @action_types
    |> Enum.flat_map(&Helpers.find_entities(actions_ast, &1))
    |> Enum.reject(&has_description?/1)
    |> Enum.map(fn {type, meta, _} = entity ->
      name = Helpers.entity_name(entity)

      format_issue(issue_meta,
        message: "Action `#{name || type}` is missing a `description`.",
        trigger: "#{name || type}",
        line_no: meta[:line]
      )
    end)
  end

  defp has_description?(entity_ast) do
    Helpers.find_in_body(entity_ast, :description) != nil or
      Keyword.has_key?(Helpers.entity_opts(entity_ast), :description)
  end
end
