defmodule AshCredo.Check.Warning.NoActions do
  use Credo.Check,
    base_priority: :normal,
    category: :warning,
    tags: [:ash],
    explanations: [
      check: """
      A resource with a data layer but no actions defined cannot be
      interacted with through the Ash API. This is almost always an
      oversight.

      Add an `actions` block:

          actions do
            defaults [:read, :destroy, create: :*, update: :*]
          end

      This check uses Ash's runtime introspection (`Ash.Resource.Info.actions/1`)
      to see the fully-resolved action list. That means it correctly handles
      resources whose actions are spliced in via `Spark.Dsl.Fragment` or
      injected by extensions - cases the AST scanner would miss and
      false-positive on.

      ## Requirements

      Your project must be compiled before running `mix credo`. If Ash is
      not available in the VM running Credo, the check is a no-op and emits
      a single diagnostic.
      """
    ]

  alias AshCredo.Introspection
  alias AshCredo.Introspection.Compiled, as: CompiledIntrospection
  alias AshCredo.Introspection.ResourceContext
  alias AshCredo.Orchestration

  @impl true
  def run(%SourceFile{} = source_file, params) do
    CompiledIntrospection.with_compiled_check(
      fn ->
        format_issue(IssueMeta.for(source_file, params),
          message:
            "Ash is not loaded in the VM running Credo - `NoActions` is a no-op. Add `:ash` as a dependency, or disable this check in `.credo.exs`.",
          line_no: 1
        )
      end,
      fn ->
        Orchestration.flat_map_loadable_resource(source_file, params, &check_loaded_resource/3)
      end
    )
  end

  defp check_loaded_resource(
         resource,
         %ResourceContext{module_ast: module_ast} = context,
         issue_meta
       ) do
    case CompiledIntrospection.actions(resource) do
      {:ok, []} ->
        [no_actions_issue(module_ast, context, issue_meta)]

      {:ok, _actions} ->
        []

      {:error, :not_loadable} ->
        CompiledIntrospection.with_unique_not_loadable(resource, fn ->
          not_loadable_issue(resource, context, issue_meta)
        end)

      {:error, _} ->
        []
    end
  end

  defp no_actions_issue(module_ast, context, issue_meta) do
    actions_ast = Introspection.find_dsl_section(module_ast, :actions)

    format_issue(issue_meta,
      message: "Resource has a data layer but no actions defined.",
      trigger: "use Ash.Resource",
      line_no: Introspection.resource_issue_line(context, actions_ast)
    )
  end

  defp not_loadable_issue(resource, context, issue_meta) do
    format_issue(issue_meta,
      message:
        "Could not load `#{inspect(resource)}` for `NoActions`. Run `mix compile` before `mix credo`, or disable this check in `.credo.exs`.",
      line_no: Map.get(context, :use_line) || 1
    )
  end
end
