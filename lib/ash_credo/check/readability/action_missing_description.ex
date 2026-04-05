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

  @action_types ~w(create read update destroy action)a

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Introspection.resource_modules()
    |> Enum.flat_map(fn module_ast ->
      module_ast
      |> Introspection.find_dsl_section(:actions)
      |> check_descriptions(issue_meta)
    end)
  end

  defp check_descriptions(nil, _issue_meta), do: []

  defp check_descriptions(actions_ast, issue_meta) do
    @action_types
    |> Enum.flat_map(&Introspection.entities(actions_ast, &1))
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
    Introspection.find_in_body(entity_ast, :description) != nil or
      Keyword.has_key?(Introspection.entity_opts(entity_ast), :description)
  end
end
