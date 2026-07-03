defmodule AshCredo.Check.Design.MissingPrimaryAction do
  use AshCredo.CompiledCheck,
    base_priority: :normal,
    category: :design,
    tags: [:ash],
    explanations: [
      check: """
      When multiple actions of the same CRUD type exist (e.g., two `:create`
      actions), one should declare `primary?: true`. Without this, Ash raises
      at runtime when framework features implicitly invoke the primary action,
      e.g. default action resolution or `manage_relationship`.

          create :register do
            primary? true
            # ...
          end

      Generic actions (type `:action`) are intentionally excluded: they are
      never invoked implicitly - callers always name them via
      `Ash.run_action/2` - so `primary?` has no behavioral effect for them. It
      is only consulted for `:create`, `:read`, `:update`, and `:destroy`.

      This check uses Ash's runtime introspection (`Ash.Resource.Info.actions/1`)
      to see the fully-resolved action list - including actions contributed by
      Spark transformers and extensions - so it catches cases where a
      transformer adds an action that breaks the primary-action invariant.

      ## Requirements

      Your project must be compiled before running `mix credo` so that the
      referenced resource modules are loadable. Typically chain them in a Mix
      alias: `lint: ["compile", "credo --strict"]`. If Ash is not loaded in the
      VM running Credo, the check is a no-op and emits a single diagnostic.
      """
    ]

  alias AshCredo.Introspection
  alias AshCredo.Introspection.Compiled, as: CompiledIntrospection
  alias AshCredo.Orchestration

  # Generic actions (`:action`) are excluded: they are never invoked implicitly,
  # so `primary?` has no behavioral effect for them.
  @action_types ~w(create read update destroy)a

  @impl AshCredo.CompiledCheck
  def run_compiled(source_file, params) do
    Orchestration.flat_map_named_resource(source_file, params, &check_resource/3)
  end

  defp check_resource(resource, context, issue_meta) do
    resource
    |> CompiledIntrospection.actions()
    |> Orchestration.with_resource_info(resource, context, issue_meta, __MODULE__, fn actions ->
      flag_missing_primaries(actions, context.module_ast, context, issue_meta)
    end)
  end

  defp flag_missing_primaries(actions, module_ast, context, issue_meta) do
    actions_line = Introspection.actions_section_line(module_ast, context)
    {counts, primaries} = summarise_actions(actions)

    for type <- @action_types,
        Map.get(counts, type, 0) > 1,
        not MapSet.member?(primaries, type) do
      format_issue(issue_meta,
        message:
          "Multiple `#{type}` actions exist on this resource but none is marked `primary?: true`.",
        trigger: "#{type}",
        line_no: actions_line
      )
    end
  end

  # Single pass over `actions` collecting both per-type counts and the set
  # of types that already have a `primary?: true` action. Avoids a per-type
  # filter+any? scan of the action list.
  defp summarise_actions(actions) do
    Enum.reduce(actions, {%{}, MapSet.new()}, fn action, {counts, primaries} ->
      next_counts = Map.update(counts, action.type, 1, &(&1 + 1))

      next_primaries =
        if action.primary?, do: MapSet.put(primaries, action.type), else: primaries

      {next_counts, next_primaries}
    end)
  end
end
