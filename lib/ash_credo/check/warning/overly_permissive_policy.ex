defmodule AshCredo.Check.Warning.OverlyPermissivePolicy do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:ash, :security],
    explanations: [
      check: """
      An unscoped policy using `authorize_if always()` allows anyone —
      including unauthenticated requests — to perform all actions.

      Scope permissive policies to specific actions or action types:

          policy action_type(:read) do
            authorize_if always()
          end

          policy action([:register, :sign_in]) do
            authorize_if always()
          end
      """
    ]

  alias AshCredo.Introspection

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Introspection.resource_contexts()
    |> Enum.flat_map(fn context ->
      context
      |> Introspection.resource_section(:policies)
      |> check_policies(issue_meta)
    end)
  end

  defp check_policies(nil, _issue_meta), do: []

  defp check_policies(policies_ast, issue_meta) do
    policies_ast
    |> Introspection.policy_entities()
    |> Enum.filter(&has_authorize_if_always?/1)
    |> Enum.reject(&scoped_policy?/1)
    |> Enum.map(fn {kind, meta, _} ->
      label = if kind == :bypass, do: "Bypass", else: "Unscoped policy"

      format_issue(issue_meta,
        message:
          "#{label} uses `authorize_if always()`, granting access to all actions including writes. Scope to specific actions or add actor-based conditions.",
        trigger: "authorize_if always()",
        line_no: meta[:line]
      )
    end)
  end

  defp has_authorize_if_always?({kind, _, _} = policy_ast) when kind in [:policy, :bypass] do
    Enum.any?(Introspection.entity_body(policy_ast), fn
      {:authorize_if, _, [{:always, _, _}]} -> true
      _ -> false
    end)
  end

  defp has_authorize_if_always?(_), do: false

  defp scoped_policy?({kind, _, [guard | _]}) when kind in [:policy, :bypass] do
    case guard do
      # policy always() — applies to everything, NOT scoped
      {:always, _, _} -> false
      # policy expr(true) — effectively unscoped
      {:expr, _, [true]} -> false
      # policy action_type(:read), policy action([...]), etc. — scoped
      _ -> true
    end
  end

  defp scoped_policy?(_), do: false
end
