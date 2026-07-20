defmodule AshCredo.Check.Warning.RedundantValidation do
  use AshCredo.CompiledCheck,
    base_priority: :normal,
    category: :warning,
    tags: [:ash],
    explanations: [
      check: """
      Flags `validate present(...)` where every referenced field is an
      attribute that already has `allow_nil? false`. The attribute
      constraint guarantees presence on its own, so the validation can
      only ever duplicate an error the changeset already carries. Straight
      from Ash's usage rules: avoid validations that duplicate attribute
      constraints.

          # Bad - allow_nil? false already rejects nil
          attributes do
            attribute :name, :string, allow_nil?: false
          end

          actions do
            create :create do
              validate present(:name)
            end
          end

          # Good - let the attribute constraint handle it
          attributes do
            attribute :name, :string, allow_nil?: false
          end

      Fields an action opens up via `allow_nil_input` are skipped: there
      the attribute may legitimately be nil at validation time (for
      example filled by the data layer during an upsert), so `present`
      does add a real constraint.

      The check also skips a field when an update or destroy action has a
      same-named `argument`. The atomic execution path is the default for
      those action types (`require_atomic?` defaults to `true`), and in
      that path the built-in `present` validation validates the argument
      instead of the attribute. The validation then enforces that the
      caller supplied the argument, regardless of the attribute
      constraint.

      In the non-atomic path the validation falls back to the attribute
      when the argument is nil, where it is indeed vacuous. But advising
      removal would silently drop the atomic-path constraint, so the check
      stays silent.

      Create actions never execute atomically, so a same-named argument on
      a create does not rescue the validation and no escape applies there.
      Validations in read and generic actions are not examined either,
      because `present` resolves against action arguments there, not
      attributes.

      ## Requirements

      Your project must be compiled before running `mix credo`. If Ash is
      not available in the VM running Credo, the check is a no-op and
      emits a single diagnostic.
      """
    ]

  alias AshCredo.Introspection
  alias AshCredo.Introspection.Compiled, as: CompiledIntrospection
  alias AshCredo.Orchestration

  # Only changeset-based actions resolve `present` against attributes (with
  # argument-to-attribute fallback); in read and generic actions it checks
  # arguments only, so attribute nullability proves nothing there.
  @changeset_action_types ~w(create update destroy)a

  @impl AshCredo.CompiledCheck
  def run_compiled(source_file, params) do
    Orchestration.flat_map_named_resource(source_file, params, &check_resource/3)
  end

  defp check_resource(resource, context, issue_meta) do
    case action_candidates(context) ++ global_candidates(context) do
      [] -> []
      candidates -> resolve_candidates(resource, context, candidates, issue_meta)
    end
  end

  defp action_candidates(context) do
    context
    |> Introspection.resource_sections(:actions)
    |> Introspection.action_entities(@changeset_action_types)
    |> Enum.flat_map(fn action_ast ->
      scope = {:action, Introspection.entity_name(action_ast)}

      action_ast
      |> Introspection.entity_body()
      |> Enum.flat_map(&parse_validate(&1, scope))
    end)
  end

  defp global_candidates(context) do
    context
    |> Introspection.resource_sections(:validations)
    |> Introspection.action_entities([:validate])
    |> Enum.flat_map(&parse_validate(&1, :global))
  end

  defp parse_validate({:validate, meta, [present_call | rest]}, scope) do
    with {:ok, fields, present_opts} <- parse_present(present_call),
         true <- counting_opts_redundant?(present_opts, length(fields)),
         true <- scope_applies?(rest, scope) do
      [%{fields: fields, line: meta[:line], scope: scope}]
    else
      _ -> []
    end
  end

  defp parse_validate(_other, _scope), do: []

  defp parse_present({:present, _, [fields]}), do: literal_fields(fields, [])

  defp parse_present({:present, _, [fields, opts]}) when is_list(opts),
    do: literal_fields(fields, opts)

  defp parse_present(_), do: :skip

  defp literal_fields(fields, opts) when is_atom(fields), do: {:ok, [fields], opts}

  defp literal_fields(fields, opts) when is_list(fields) do
    if Enum.all?(fields, &is_atom/1), do: {:ok, fields, opts}, else: :skip
  end

  defp literal_fields(_fields, _opts), do: :skip

  # The bare builtin expands to `exactly: count`, which always-present
  # attributes always satisfy; an explicit `at_least` up to the field count
  # likewise. Explicit `exactly`/`at_most` (e.g. `exactly: 0` for "must be
  # absent") or non-literal options change the semantics, so skip them.
  defp counting_opts_redundant?([], _count), do: true

  defp counting_opts_redundant?(opts, count) do
    Enum.all?(opts, fn
      {:at_least, at_least} -> is_integer(at_least) and at_least <= count
      _other -> false
    end)
  end

  # `where`, `message`, and do-blocks never make an always-satisfied
  # validation meaningful again, so action-level candidates always apply.
  defp scope_applies?(_rest, {:action, _name}), do: true

  # Global validations default to `on: [:create, :update]`; an explicit
  # `on` must stay within the changeset action types for attribute
  # presence to apply.
  defp scope_applies?(rest, :global) do
    case find_on_option(rest) do
      nil -> true
      {:found, on} -> on |> List.wrap() |> Enum.all?(&(&1 in @changeset_action_types))
    end
  end

  defp find_on_option(rest) do
    Enum.find_value(rest, fn
      opts when is_list(opts) ->
        Enum.find_value(opts, fn
          {:on, value} -> {:found, value}
          {:do, block} -> block_on(block)
          _other -> nil
        end)

      _other ->
        nil
    end)
  end

  defp block_on({:__block__, _, entries}), do: Enum.find_value(entries, &entry_on/1)
  defp block_on(entry), do: entry_on(entry)

  defp entry_on({:on, _, [value]}), do: {:found, value}
  defp entry_on(_entry), do: nil

  defp resolve_candidates(resource, context, candidates, issue_meta) do
    resource
    |> CompiledIntrospection.inspect_module()
    |> Orchestration.with_resource_info(resource, context, issue_meta, __MODULE__, fn
      %{attributes: attributes, actions: actions} ->
        flag_redundant(resource, candidates, attributes, actions, issue_meta)
    end)
  end

  defp flag_redundant(resource, candidates, attributes, actions, issue_meta) do
    non_nullable =
      attributes
      |> Enum.filter(&(&1.allow_nil? == false))
      |> MapSet.new(& &1.name)

    candidates
    |> Enum.filter(&redundant?(&1, non_nullable, actions))
    |> Enum.map(&redundant_issue(&1, resource, issue_meta))
  end

  defp redundant?(%{fields: fields, scope: scope}, non_nullable, actions) do
    Enum.all?(fields, &MapSet.member?(non_nullable, &1)) and
      no_input_overrides?(fields, scope, actions)
  end

  # An action-level input can make `present` meaningful again despite the
  # attribute constraint: `allow_nil_input` reopens the attribute, and a
  # same-named `argument` redirects `present` to validate the argument in
  # the atomic path (Ash.Resource.Validation.Present.atomic/3; the
  # non-atomic path falls back to the attribute, but removal would drop
  # the atomic-path constraint, so skip conservatively). Only update and
  # destroy actions have an atomic path (`require_atomic?` exists on
  # neither the create struct nor the create execution), so on creates the
  # argument never rescues the validation and no escape applies.
  defp no_input_overrides?(fields, {:action, action_name}, actions) do
    case Enum.find(actions, &(&1.name == action_name)) do
      # The source names an action the compiled module does not have (a
      # stale build or fragment drift) - do not flag what we cannot
      # resolve.
      nil -> false
      action -> Enum.all?(fields, &(&1 not in overriding_inputs(action)))
    end
  end

  defp no_input_overrides?(fields, :global, actions) do
    overriding = Enum.flat_map(actions, &overriding_inputs/1)
    Enum.all?(fields, &(&1 not in overriding))
  end

  defp overriding_inputs(action), do: argument_names(action) ++ nullable_inputs(action)

  @atomic_action_types ~w(update destroy)a

  defp argument_names(%{type: type} = action) when type in @atomic_action_types do
    action |> Map.get(:arguments) |> List.wrap() |> Enum.map(& &1.name)
  end

  defp argument_names(_action), do: []

  defp nullable_inputs(action), do: List.wrap(Map.get(action, :allow_nil_input) || [])

  defp redundant_issue(%{fields: fields, line: line}, resource, issue_meta) do
    format_issue(issue_meta,
      message: message(fields, resource),
      trigger: "present",
      line_no: line
    )
  end

  defp message([field], resource) do
    "`validate present(:#{field})` is redundant: attribute `:#{field}` on " <>
      "`#{inspect(resource)}` already has `allow_nil? false`, which guarantees presence. " <>
      "Remove the validation - Ash's usage rules advise against validations that " <>
      "duplicate attribute constraints."
  end

  defp message(fields, resource) do
    listed = Enum.map_join(fields, ", ", &":#{&1}")

    "`validate present(...)` on #{listed} is redundant: these attributes on " <>
      "`#{inspect(resource)}` already have `allow_nil? false`, which guarantees presence. " <>
      "Remove the validation - Ash's usage rules advise against validations that " <>
      "duplicate attribute constraints."
  end
end
