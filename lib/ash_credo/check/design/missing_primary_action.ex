defmodule AshCredo.Check.Design.MissingPrimaryAction do
  use Credo.Check,
    base_priority: :normal,
    category: :design,
    tags: [:ash],
    explanations: [
      check: """
      When multiple actions of the same type exist (e.g., two `:create` actions),
      one should declare `primary?: true`. Without this, Ash raises at runtime
      when framework features implicitly invoke the primary action.

          create :register do
            primary? true
            # ...
          end
      """
    ]

  alias AshCredo.Introspection

  @action_types ~w(create read update destroy)a

  @impl true
  def run(%SourceFile{} = source_file, params) do
    if Introspection.ash_resource?(source_file) do
      actions_ast = Introspection.find_dsl_section(source_file, :actions)
      check_primary_actions(actions_ast, source_file, params)
    else
      []
    end
  end

  defp check_primary_actions(nil, _source_file, _params), do: []

  defp check_primary_actions(actions_ast, source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    @action_types
    |> Enum.flat_map(fn type ->
      actions = Introspection.entities(actions_ast, type)
      types_missing_primary(type, actions)
    end)
    |> Enum.map(fn {type, actions} ->
      first = hd(actions)
      {_, meta, _} = first

      format_issue(issue_meta,
        message: "Multiple `#{type}` actions exist but none is marked `primary?: true`.",
        trigger: "#{type}",
        line_no: meta[:line]
      )
    end)
  end

  defp types_missing_primary(_type, actions) when length(actions) <= 1, do: []

  defp types_missing_primary(type, actions) do
    if Enum.any?(actions, &has_primary_opt?/1), do: [], else: [{type, actions}]
  end

  defp has_primary_opt?(entity_ast) do
    Introspection.entity_has_opt?(entity_ast, :primary?, true)
  end
end
