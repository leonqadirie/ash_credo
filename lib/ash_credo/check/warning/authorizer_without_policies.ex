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
      """
    ]

  alias AshCredo.Introspection

  @policy_authorizer [:Ash, :Policy, :Authorizer]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Introspection.resource_modules()
    |> Enum.flat_map(&authorizer_without_policies_issues(&1, issue_meta))
  end

  defp authorizer_without_policies_issues(module_ast, issue_meta) do
    context = Introspection.resource_context(module_ast)
    authorizer_line = find_authorizer_line(context)
    policies_ast = Introspection.find_dsl_section(context, :policies)
    has_policies = Introspection.policy_entities(policies_ast) != []

    if authorizer_line != nil and not has_policies do
      [
        format_issue(issue_meta,
          message:
            "Resource has Ash.Policy.Authorizer but no policies defined. All actions will be denied.",
          trigger: "Ash.Policy.Authorizer",
          line_no: authorizer_line
        )
      ]
    else
      []
    end
  end

  defp find_authorizer_line(%{use_opts: opts} = context) when is_list(opts) do
    opts
    |> Keyword.get(:authorizers)
    |> authorizer_line(context)
  end

  defp find_authorizer_line(_), do: nil

  defp authorizer_line(authorizers, context) when is_list(authorizers) do
    Enum.find_value(authorizers, &authorizer_line(&1, context))
  end

  defp authorizer_line({:__aliases__, meta, _segments} = ref_ast, context) do
    if Introspection.module_ref?(ref_ast, context, @policy_authorizer), do: meta[:line]
  end

  defp authorizer_line(_, _), do: nil
end
