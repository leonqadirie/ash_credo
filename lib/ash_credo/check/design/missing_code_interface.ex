defmodule AshCredo.Check.Design.MissingCodeInterface do
  use Credo.Check,
    base_priority: :low,
    category: :design,
    tags: [:ash],
    explanations: [
      check: """
      Resources with actions but no `code_interface` block miss out on Ash's
      generated typed functions. This check inspects each resource's fully
      resolved action list via `Ash.Resource.Info.actions/1` and, for every
      action that has neither a resource-level nor a domain-level code
      interface targeting it, emits a dedicated issue naming the missing
      action.

          # Flagged - action `:published` has no interface anywhere
          actions do
            read :published
          end

          # Preferred - one of:
          code_interface do
            define :published
          end
          # ...or on the domain:
          resources do
            resource MyApp.Post do
              define :published
            end
          end

      ## Requirements

      Your project must be compiled before running `mix credo`. If Ash is
      not available in the VM running Credo, the check is a no-op and emits
      a single diagnostic.
      """
    ]

  alias AshCredo.Introspection
  alias AshCredo.Introspection.Compiled, as: CompiledIntrospection

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    CompiledIntrospection.with_compiled_check(
      fn ->
        format_issue(issue_meta,
          message:
            "Ash is not loaded in the VM running Credo - `MissingCodeInterface` is a no-op. Add `:ash` as a dependency, or disable this check in `.credo.exs`.",
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
         %{absolute_segments: segments, module_ast: module_ast} = context,
         issue_meta
       ) do
    resource = Module.concat(segments)

    with false <- Introspection.embedded_resource?(context),
         {:ok, info} <- CompiledIntrospection.inspect_module(resource) do
      flag_missing_interfaces(resource, info, module_ast, context, issue_meta)
    else
      true ->
        []

      {:error, :not_loadable} ->
        CompiledIntrospection.with_unique_not_loadable(resource, fn ->
          not_loadable_issue(resource, context, issue_meta)
        end)

      {:error, _} ->
        []
    end
  end

  defp flag_missing_interfaces(
         resource,
         %{actions: actions, interfaces: interfaces, domain: resource_domain},
         module_ast,
         context,
         issue_meta
       ) do
    actions_line = actions_section_line(module_ast, context)

    actions
    |> Enum.reject(&action_has_interface?(&1, interfaces, resource_domain, resource))
    |> Enum.map(&missing_interface_issue(&1, resource, actions_line, issue_meta))
  end

  defp action_has_interface?(action, interfaces, resource_domain, resource) do
    not is_nil(CompiledIntrospection.find_interface(interfaces, action.name)) or
      not is_nil(CompiledIntrospection.domain_interface(resource_domain, resource, action.name))
  end

  defp missing_interface_issue(action, resource, line, issue_meta) do
    format_issue(issue_meta,
      message:
        "Action `:#{action.name}` on `#{inspect(resource)}` has no code interface. " <>
          "Define one with `define :#{action.name}` in the resource's `code_interface` block, " <>
          "or `define :some_name, action: :#{action.name}` in the domain's `resource` reference.",
      trigger: "#{action.name}",
      line_no: line
    )
  end

  defp actions_section_line(module_ast, context) do
    actions_ast = Introspection.find_dsl_section(module_ast, :actions)

    Introspection.section_issue_line(actions_ast, Map.get(context, :use_line), 1)
  end

  defp not_loadable_issue(resource, context, issue_meta) do
    format_issue(issue_meta,
      message:
        "Could not load `#{inspect(resource)}` for `MissingCodeInterface`. Run `mix compile` before `mix credo`, or disable this check in `.credo.exs`.",
      line_no: Map.get(context, :use_line) || 1
    )
  end
end
