defmodule AshCredo.Check.Warning.AuthorizerWithoutPolicies do
  use AshCredo.CompiledCheck,
    base_priority: :high,
    category: :warning,
    tags: [:ash, :security],
    explanations: [
      check: """
      A resource that declares `Ash.Policy.Authorizer` but defines no
      policies denies all actions by default. An empty `policies` block has
      the same effect. This is almost always unintentional.

      Either add policies:

          policies do
            policy action_type(:read) do
              authorize_if actor_attribute_equals(:active, true)
            end
          end

      Or remove the authorizer if you don't need authorization yet.

      The check uses Ash's runtime introspection
      (`Ash.Resource.Info.authorizers/1` and `Ash.Policy.Info.policies/1`)
      to read the fully resolved authorizer and policy lists, so it
      correctly handles authorizers added by extensions and policies
      declared in `Spark.Dsl.Fragment` modules - cases an AST scanner
      cannot see.

      ## Requirements

      Compile your project before running `mix credo`. If Ash is not
      available in the VM running Credo, the check is a no-op and emits a
      single diagnostic.
      """
    ]

  alias AshCredo.Introspection.Compiled, as: CompiledIntrospection
  alias AshCredo.Orchestration

  @impl AshCredo.CompiledCheck
  def run_compiled(source_file, params) do
    Orchestration.flat_map_named_resource(source_file, params, &check_resource/3)
  end

  defp check_resource(resource, context, issue_meta) do
    resource
    |> CompiledIntrospection.inspect_module()
    |> Orchestration.with_resource_info(resource, context, issue_meta, __MODULE__, fn info ->
      flag_if_authorizer_without_policies(resource, info, context, issue_meta)
    end)
  end

  defp flag_if_authorizer_without_policies(
         _resource,
         %{authorizers: authorizers, policies: policies},
         context,
         issue_meta
       ) do
    # `Ash.Policy.Authorizer` here is deliberately a bare atom literal, not
    # a remote call. Elixir compiles it to `:"Elixir.Ash.Policy.Authorizer"`
    # without ever loading the module, so this file compiles cleanly in
    # projects that don't depend on Ash. If you ever turn this into a
    # remote call (e.g. `Ash.Policy.Authorizer.something()`), make sure the
    # `@compile {:no_warn_undefined, ...}` list in
    # `AshCredo.Introspection.Compiled` still covers it (it currently does,
    # defensively).
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
      line_no: context.use_line || 1
    )
  end
end
