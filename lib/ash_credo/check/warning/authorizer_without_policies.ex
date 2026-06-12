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
      extensions and policies declared in `Spark.Dsl.Fragment` modules - cases
      the AST scanner would silently miss.

      ## Requirements

      Your project must be compiled before running `mix credo`. If Ash is
      not available in the VM running Credo, the check is a no-op and emits
      a single diagnostic.
      """
    ]

  alias AshCredo.Introspection.Compiled, as: CompiledIntrospection
  alias AshCredo.Orchestration

  @impl true
  def run(%SourceFile{} = source_file, params) do
    Orchestration.compiled_check_on_named_resources(
      source_file,
      params,
      __MODULE__,
      &check_resource/3
    )
  end

  defp check_resource(resource, context, issue_meta) do
    case CompiledIntrospection.inspect_module(resource) do
      {:ok, info} ->
        flag_if_authorizer_without_policies(resource, info, context, issue_meta)

      {:error, :not_loadable} ->
        Orchestration.unique_not_loadable_issues(resource, context, issue_meta, __MODULE__)

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
    # `Ash.Policy.Authorizer` here is intentionally a bare atom literal, not
    # a remote call - Elixir compiles it to `:"Elixir.Ash.Policy.Authorizer"`
    # without ever needing the module loaded, so this file compiles cleanly
    # in projects that don't depend on Ash. If you ever turn this into a
    # remote call (e.g. `Ash.Policy.Authorizer.something()`), make sure
    # `AshCredo.Introspection.Compiled`'s `@compile {:no_warn_undefined,
    # ...}` list still covers it (it currently does, defensively).
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
end
