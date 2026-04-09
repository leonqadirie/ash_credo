defmodule AshCredo.Check.Warning.AuthorizerWithoutPolicies do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:ash, :security],
    explanations: [
      check: """
      Resources that declare `Ash.Policy.Authorizer` but define no policies
      will deny all actions by default. An empty `policies` block has the same
      effect. This is almost always unintentional.

      Either add policies:

          policies do
            policy action_type(:read) do
              authorize_if actor_attribute_equals(:active, true)
            end
          end

      Or remove the authorizer if authorization is not needed yet.

      This check uses Ash's runtime introspection (`Ash.Resource.Info.authorizers/1`
      and `Ash.Policy.Info.policies/1`) to see the fully-resolved authorizer
      and policy lists. That means it correctly handles authorizers added by
      extensions and policies declared in `Spark.Dsl.Fragment` modules — cases
      the AST scanner would silently miss.

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
            "Ash is not loaded in the VM running Credo — `AuthorizerWithoutPolicies` is a no-op. Add `:ash` as a dependency, or disable this check in `.credo.exs`.",
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

  defp check_resource(%{absolute_segments: segments} = context, issue_meta) do
    resource = Module.concat(segments)

    case CompiledIntrospection.inspect_module(resource) do
      {:ok, info} ->
        flag_if_authorizer_without_policies(resource, info, context, issue_meta)

      {:error, :not_loadable} ->
        [not_loadable_issue(resource, context, issue_meta)]

      {:error, _} ->
        []
    end
  end

  defp flag_if_authorizer_without_policies(
         _resource,
         %{authorizers: authorizers, policies: policies},
         context,
         issue_meta
       ) do
    if Ash.Policy.Authorizer in authorizers and policies == [] do
      [missing_policies_issue(context, issue_meta)]
    else
      []
    end
  end

  defp missing_policies_issue(context, issue_meta) do
    format_issue(issue_meta,
      message:
        "Resource has Ash.Policy.Authorizer but no policies defined. All actions will be denied.",
      trigger: "Ash.Policy.Authorizer",
      line_no: Map.get(context, :use_line) || 1
    )
  end

  defp not_loadable_issue(resource, context, issue_meta) do
    format_issue(issue_meta,
      message:
        "Could not load `#{inspect(resource)}` for `AuthorizerWithoutPolicies`. Run `mix compile` before `mix credo`, or disable this check in `.credo.exs`.",
      line_no: Map.get(context, :use_line) || 1
    )
  end
end
