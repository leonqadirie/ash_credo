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

  @action_types ~w(create read update destroy action)a

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    CompiledIntrospection.with_compiled_check(
      fn ->
        format_issue(issue_meta,
          message:
            "Ash is not loaded in the VM running Credo - `MissingPrimaryAction` is a no-op. Add `:ash` as a dependency, or disable this check in `.credo.exs`.",
          line_no: 1
        )
      end,
      fn ->
        source_file
        |> Introspection.resource_contexts()
        |> Enum.flat_map(&check_resource(&1, issue_meta))
      end
    )
  end

  defp check_resource(%{absolute_segments: nil}, _issue_meta), do: []

  defp check_resource(
         %{module_ast: module_ast, absolute_segments: segments} = context,
         issue_meta
       ) do
    resource = Module.concat(segments)

    case CompiledIntrospection.actions(resource) do
      {:ok, actions} ->
        flag_missing_primaries(actions, module_ast, context, issue_meta)

      {:error, :not_loadable} ->
        CompiledIntrospection.with_unique_not_loadable(resource, fn ->
          not_loadable_issue(resource, context, issue_meta)
        end)

      {:error, _} ->
        []
    end
  end

  defp flag_missing_primaries(actions, module_ast, context, issue_meta) do
    actions_line = actions_section_line(module_ast, context)

    @action_types
    |> Enum.map(fn type -> {type, Enum.filter(actions, &(&1.type == type))} end)
    |> Enum.reject(fn {_type, actions} ->
      length(actions) <= 1 or Enum.any?(actions, & &1.primary?)
    end)
    |> Enum.map(fn {type, _actions} ->
      format_issue(issue_meta,
        message:
          "Multiple `#{type}` actions exist on this resource but none is marked `primary?: true`.",
        trigger: "#{type}",
        line_no: actions_line
      )
    end)
  end

  defp actions_section_line(module_ast, context) do
    actions_ast = Introspection.find_dsl_section(module_ast, :actions)

    Introspection.section_issue_line(actions_ast, Map.get(context, :use_line), 1)
  end

  defp not_loadable_issue(resource, context, issue_meta) do
    format_issue(issue_meta,
      message:
        "Could not load `#{inspect(resource)}` for `MissingPrimaryAction`. Run `mix compile` before `mix credo`, or disable this check in `.credo.exs`.",
      line_no: Map.get(context, :use_line) || 1
    )
  end
end
