defmodule AshCredo.Check.Warning.OverlyPermissivePolicy do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:ash, :security],
    explanations: [
      check: """
      An unscoped policy using `authorize_if always()` allows anyone,
      including unauthenticated requests, to perform all actions.

      A policy is unscoped when its condition is `always()` or
      `expr(true)`, when every element of a list condition is one of
      those, when it has no condition at all (Ash defaults the condition
      to true), or when its only body-level `condition` is
      `always()`/`expr(true)`.

      Conditions on enclosing `policy_group`s count: Ash adds them to
      every policy the group contains, so a policy inside
      `policy_group actor_attribute_equals(:role, :admin)`
      is scoped even without a condition of its own.

      Entity options do not scope the policy: `policy description: "..." do`
      still applies everywhere. The check recognizes the condition whether
      you pass it positionally or via the `condition:` option.

      Checks apply top to bottom and the first one that reaches a decision
      wins, so `authorize_if always()` after a `forbid_if` or
      `forbid_unless` is the deliberate allow-all-except pattern and is
      not flagged. Guards that can never deny do not count
      (`forbid_if never()`, `forbid_unless always()`, boolean literals):

          policy always() do
            forbid_if actor_attribute_equals(:banned, true)
            authorize_if always()
          end

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

  defp check_policies(policies_ast, issue_meta) do
    policies_ast
    |> Introspection.policy_entities_with_conditions()
    |> Enum.filter(fn {entity, _conditions} -> unguarded_authorize_always?(entity) end)
    |> Enum.reject(fn {entity, inherited_conditions} ->
      scoped_policy?(entity) or Enum.any?(inherited_conditions, &scoped_condition?/1)
    end)
    |> Enum.map(fn {{kind, meta, _}, _conditions} ->
      label = if kind == :bypass, do: "Bypass", else: "Unscoped policy"

      format_issue(issue_meta,
        message:
          "#{label} uses `authorize_if always()`, granting access to all actions including writes. Scope to specific actions or add actor-based conditions.",
        trigger: "authorize_if always()",
        line_no: meta[:line]
      )
    end)
  end

  # Checks apply top to bottom and the first decision wins, so
  # `authorize_if always()` only grants unconditional access when no
  # earlier `forbid_if`/`forbid_unless` can deny first; with such a guard,
  # this is the deliberate allow-all-except pattern. Guards that can never
  # fire (`forbid_if never()`/`expr(false)`/`false`, `forbid_unless
  # always()`/`expr(true)`/`true`) do not count. Checks accept a trailing
  # options list (`forbid_if never(), name: "..."`), which does not change
  # the check itself.
  defp unguarded_authorize_always?({kind, _, _} = policy_ast) when kind in [:policy, :bypass] do
    policy_ast
    |> Introspection.entity_body()
    |> Enum.reduce_while(false, fn
      {forbid, _, [check | _opts]}, acc when forbid in [:forbid_if, :forbid_unless] ->
        if noop_forbid?(forbid, check), do: {:cont, acc}, else: {:halt, false}

      {forbid, _, _}, _acc when forbid in [:forbid_if, :forbid_unless] ->
        {:halt, false}

      {:authorize_if, _, [{:always, _, _} | _opts]}, _acc ->
        {:halt, true}

      _other, acc ->
        {:cont, acc}
    end)
  end

  defp unguarded_authorize_always?(_), do: false

  defp noop_forbid?(:forbid_if, {:never, _, _}), do: true
  defp noop_forbid?(:forbid_if, {:expr, _, [false]}), do: true
  defp noop_forbid?(:forbid_if, false), do: true
  defp noop_forbid?(:forbid_unless, check), do: unscoped_condition?(check)
  defp noop_forbid?(_forbid, _check), do: false

  defp scoped_policy?({kind, _, args} = policy_ast) when kind in [:policy, :bypass] do
    case Enum.reject(args, &do_block?/1) do
      # For `policy do ... end`, Ash defaults the condition to static true, so
      # the policy is only scoped if its body declares a restrictive `condition`
      [] -> scoped_body_condition?(policy_ast)
      [condition_or_opts | _] -> scoped_condition_arg?(condition_or_opts, policy_ast)
    end
  end

  defp scoped_policy?(_), do: false

  defp do_block?([{:do, _} | _]), do: true
  defp do_block?(_), do: false

  # The condition arg is optional and the entity takes options
  # (`policy description: "..." do`), so a keyword list of known policy
  # option keys is options, not a condition; the condition, if any, is
  # its `:condition` key.
  @policy_option_keys ~w(description access_type condition error_message)a

  defp scoped_condition_arg?(arg, policy_ast) do
    if policy_opts?(arg) do
      case Keyword.fetch(arg, :condition) do
        {:ok, condition} -> scoped_condition?(condition)
        :error -> scoped_body_condition?(policy_ast)
      end
    else
      scoped_condition?(arg)
    end
  end

  defp policy_opts?(arg) do
    Keyword.keyword?(arg) and arg != [] and
      Enum.all?(arg, fn {key, _} -> key in @policy_option_keys end)
  end

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

  # always() applies to everything; expr(true) and a bare `true` literal
  # (Ash accepts booleans as checks) are effectively unscoped. Anything
  # else (action_type(:read), action([...]), actor checks) scopes the
  # policy.
  defp unscoped_condition?({:always, _, _}), do: true
  defp unscoped_condition?({:expr, _, [true]}), do: true
  defp unscoped_condition?(true), do: true
  defp unscoped_condition?(_), do: false
end
