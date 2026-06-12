defmodule AshCredo.Check.Warning.OverlyPermissivePolicy do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:ash, :security],
    explanations: [
      check: """
      An unscoped policy using `authorize_if always()` allows anyone -
      including unauthenticated requests - to perform all actions.

      A policy is unscoped when its condition is `always()` or `expr(true)`,
      when every element of a list condition is one of those, when it has no
      condition at all (Ash defaults the condition to true), or when its only
      body-level `condition` is `always()`/`expr(true)`.

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
  alias AshCredo.Orchestration

  @impl true
  def run(%SourceFile{} = source_file, params),
    do: Orchestration.flat_map_resource_section(source_file, params, :policies, &check_policies/2)

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

  defp scoped_policy?({kind, _, args} = policy_ast) when kind in [:policy, :bypass] do
    case Enum.reject(args, &do_block?/1) do
      # policy do ... end - Ash defaults the condition to static true, so the
      # policy is only scoped if its body declares a restrictive `condition`
      [] -> scoped_body_condition?(policy_ast)
      [condition | _] -> scoped_condition?(condition)
    end
  end

  defp scoped_policy?(_), do: false

  defp do_block?([{:do, _} | _]), do: true
  defp do_block?(_), do: false

  defp scoped_body_condition?(policy_ast) do
    Enum.any?(Introspection.entity_body(policy_ast), fn
      {:condition, _, [condition]} -> scoped_condition?(condition)
      _ -> false
    end)
  end

  # Ash ANDs list conditions, so a list is unscoped only when every element
  # is unscoped (an empty list has no restricting element at all)
  defp scoped_condition?(condition) when is_list(condition),
    do: not Enum.all?(condition, &unscoped_condition?/1)

  defp scoped_condition?(condition), do: not unscoped_condition?(condition)

  # always() applies to everything; expr(true) is effectively unscoped.
  # Anything else - action_type(:read), action([...]), actor checks - scopes.
  defp unscoped_condition?({:always, _, _}), do: true
  defp unscoped_condition?({:expr, _, [true]}), do: true
  defp unscoped_condition?(_), do: false
end
