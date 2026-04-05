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

  @impl true
  def run(%SourceFile{} = source_file, params) do
    if Introspection.ash_resource?(source_file) do
      authorizer_line = find_authorizer_line(source_file)

      policies_ast = Introspection.find_dsl_section(source_file, :policies)

      has_policies =
        Introspection.policy_entities(policies_ast) != []

      if authorizer_line != nil and not has_policies do
        issue_meta = IssueMeta.for(source_file, params)

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
    else
      []
    end
  end

  defp find_authorizer_line(source_file) do
    case Introspection.use_opts(source_file, [:Ash, :Resource]) do
      opts when is_list(opts) ->
        opts
        |> Keyword.get(:authorizers)
        |> authorizer_line()

      _ ->
        nil
    end
  end

  defp authorizer_line(authorizers) when is_list(authorizers) do
    Enum.find_value(authorizers, &authorizer_line/1)
  end

  defp authorizer_line({:__aliases__, meta, [:Ash, :Policy, :Authorizer]}), do: meta[:line]
  defp authorizer_line(_), do: nil
end
