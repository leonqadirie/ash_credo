defmodule AshCredo.Check.Warning.MissingChangeWrapper do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:ash],
    explanations: [
      check: """
      Builtin change functions like `manage_relationship`, `set_attribute`, and
      `relate_actor` must be wrapped in `change` when used inside an action body.

      Without the wrapper, the function call returns a change reference tuple that
      is silently discarded — the change never runs and no error is raised.

          # Bad — compiles but silently does nothing
          create :some_action do
            argument :thing, :map
            manage_relationship(:thing, :thing, type: :create)
          end

          # Good — wrapped in change
          create :some_action do
            argument :thing, :map
            change manage_relationship(:thing, :thing, type: :create)
          end
      """
    ]

  alias AshCredo.Introspection

  @action_types ~w(create update destroy action)a

  @naked_change_fns ~w(
    manage_relationship
    relate_actor
    set_attribute
    set_new_attribute
    set_context
    atomic_set
    atomic_update
    increment
    cascade_destroy
    cascade_update
    optimistic_lock
    prevent_change
    ensure_selected
    get_and_lock
    get_and_lock_for_update
    debug_log
  )a

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Introspection.resource_modules()
    |> Enum.flat_map(fn module_ast ->
      module_ast
      |> Introspection.find_dsl_section(:actions)
      |> check_actions(issue_meta)
    end)
  end

  defp check_actions(nil, _issue_meta), do: []

  defp check_actions(actions_ast, issue_meta) do
    @action_types
    |> Enum.flat_map(&Introspection.entities(actions_ast, &1))
    |> Enum.flat_map(&find_naked_changes(&1, issue_meta))
  end

  defp find_naked_changes(action_ast, issue_meta) do
    action_ast
    |> Introspection.entity_body()
    |> Enum.filter(&naked_change?/1)
    |> Enum.map(fn {func_name, meta, _} ->
      format_issue(issue_meta,
        message:
          "`#{func_name}` has no effect without a `change` wrapper. " <>
            "Use `change #{func_name}(...)` instead.",
        trigger: "#{func_name}",
        line_no: meta[:line]
      )
    end)
  end

  defp naked_change?({func_name, _, _}) when func_name in @naked_change_fns, do: true
  defp naked_change?(_), do: false
end
