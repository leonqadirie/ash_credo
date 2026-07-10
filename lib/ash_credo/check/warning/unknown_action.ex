defmodule AshCredo.Check.Warning.UnknownAction do
  use AshCredo.CompiledCheck,
    base_priority: :high,
    category: :warning,
    tags: [:ash],
    explanations: [
      check: """
      Flags raw `Ash.*` API calls that reference an action that does not
      exist on the resolved resource. Catches typos at lint time:

          Ash.read!(MyApp.Post, action: :publishd)
          #                             ^^^^^^^^ - no such action
          # Did you mean `:published`?

      The check uses Ash's runtime introspection
      (`Ash.Resource.Info.actions/1`) to read the resource's fully-resolved
      action list, then jaro-distance to suggest the closest known action
      name when one is similar enough.

      Unlike `Refactor.UseCodeInterface`, this check is objective: the
      action either exists on the resource or it doesn't. There's nothing
      to configure.

      It runs against the same resolved Ash call-site pipeline as
      `UseCodeInterface`, including
      `Ash.read!`/`Ash.get!`/`Ash.read_one!`/`Ash.read_first!`/`Ash.bulk_*`/
      `Ash.Changeset.for_*`/`Ash.Query.for_read`/`Ash.ActionInput.for_action` - whenever both
      the resource and the action argument are literal values that can be
      resolved at lint time.

      ## Requirements

      Your project must be compiled before running `mix credo`. If Ash is
      not available in the VM running Credo, the check is a no-op and
      emits a single diagnostic.
      """
    ]

  alias AshCredo.Introspection.{AshCallResolver, AshCallSite}
  alias AshCredo.Introspection.Compiled, as: CompiledIntrospection

  @impl AshCredo.CompiledCheck
  def run_compiled(source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> AshCallResolver.sites()
    |> Enum.flat_map(&check_site(&1, issue_meta))
  end

  defp check_site(%AshCallSite{resolution: {:ok, resource, info}} = site, issue_meta) do
    case CompiledIntrospection.action(resource, site.action_name) do
      {:error, :unknown_action} ->
        [unknown_action_issue(resource, info.actions, site, issue_meta)]

      _ ->
        []
    end
  end

  # `:not_loadable` resources are reported by `UseCodeInterface` (gated on its
  # `enforce_code_interface_outside_domain` flag) - emitting a second
  # "could not load" diagnostic from here would just double the noise.
  defp check_site(%AshCallSite{}, _issue_meta), do: []

  defp unknown_action_issue(resource, known_actions, site, issue_meta) do
    qualified = AshCallResolver.qualified_call(site)
    suggestion = suggest_action_name(known_actions, site.action_name)

    hint =
      case suggestion do
        nil -> ""
        name -> " Did you mean `:#{name}`?"
      end

    format_issue(issue_meta,
      message:
        "Unknown action `:#{site.action_name}` on `#{inspect(resource)}` (called via `#{qualified}/#{site.arity}`).#{hint}",
      trigger: qualified,
      line_no: site.call_meta[:line]
    )
  end

  # Returns the known action name most similar to `target_name` (jaro distance
  # >= 0.75), or nil if no close match exists. Pure string similarity over the
  # already-resolved action list - no Ash runtime introspection, so it lives
  # with its sole caller rather than in the Compiled gateway.
  defp suggest_action_name(known_actions, target_name)
       when is_list(known_actions) and is_atom(target_name) do
    target_str = Atom.to_string(target_name)

    scored =
      known_actions
      |> Enum.map(fn action ->
        {action.name, String.jaro_distance(target_str, Atom.to_string(action.name))}
      end)
      |> Enum.filter(fn {_, score} -> score >= 0.75 end)

    case scored do
      [] -> nil
      candidates -> candidates |> Enum.max_by(&elem(&1, 1)) |> elem(0)
    end
  end
end
