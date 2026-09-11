defmodule AshCredo.Check.Warning.RepoCallInResource do
  use Credo.Check,
    base_priority: :normal,
    category: :warning,
    tags: [:ash, :security],
    param_defaults: [
      flagged_functions: [
        :query,
        :query!,
        :query_many,
        :query_many!,
        :insert_all,
        :update_all,
        :delete_all
      ],
      repo_names: [:Repo],
      excluded_paths: AshCredo.PathFilter.default_excluded_paths()
    ],
    explanations: [
      check: """
      Calling an Ecto repo directly from inside a resource, or from one of
      its change, validation, preparation, calculation, or generic action
      modules, can
      bypass what the resource is configured to manage: tenant scoping,
      notifications, and timestamps. The enclosing action's policies were
      checked for the record being acted on, but not for any other rows a
      raw statement touches.

          # Bad - raw SQL inside a change module skips the framework
          defmodule MyApp.Order.Changes.AssignStops do
            use Ash.Resource.Change

            def change(changeset, _opts, context) do
              MyApp.Repo.query!(
                "UPDATE orders SET current_stop_id = ... WHERE ...",
                [order_ids, stop_ids]
              )

              changeset
            end
          end

          # Good - per-row bulk writes go through the action layer.
          # `Ash.update_many` applies atomic changes as a single statement.
          order_stop_pairs
          |> Enum.map(fn {id, stop_id} -> {%{id: id}, %{current_stop_id: stop_id}} end)
          |> Ash.update_many(MyApp.Order, :set_current_stop, tenant: tenant)

      The check flags calls to repo functions that execute queries
      (`query`, `query!`, `query_many`, `query_many!`, `insert_all`,
      `update_all`, `delete_all`, plus `Ecto.Adapters.SQL.query`/`query!`)
      on any module whose last name segment is `Repo` - or another name
      you list in `repo_names` - but only inside modules that
      `use Ash.Resource`, `Ash.Resource.Change`,
      `Ash.Resource.Validation`, `Ash.Resource.Preparation`,
      `Ash.Resource.Calculation`, or
      `Ash.Resource.Actions.Implementation`. The same calls in a
      controller, worker, or plain context module are not flagged -
      outside those modules they are ordinary Ecto.

      `Repo.transaction/1` is deliberately not flagged: wrapping Ash calls
      in a manual transaction is transaction control, not a bypass. Only
      the functions that execute queries themselves are reported. For the
      same reason, custom `Ash.DataLayer` implementations and
      `Ash.Resource.ManualRelationship` modules are not checked - talking
      to Ecto directly is their job.

      Repo read functions (`all`, `one`, `get`, `get_by`, `exists?`,
      `aggregate`, ...) also bypass tenancy and policies, but they are not
      in the default set. The defaults cover writes and raw SQL, where a
      bypass silently corrupts data. Add the read functions to
      `flagged_functions` to flag them too.

      Raw SQL is sometimes the right tool (recursive CTEs, advisory
      locks). When it is intentional, silence the call site explicitly:

          # credo:disable-for-next-line AshCredo.Check.Warning.RepoCallInResource
          MyApp.Repo.query!("SELECT pg_advisory_xact_lock($1)", [key])

      Test directories are excluded by default. Migrations and seeds under
      `priv/` are never scanned because Credo's default `files.included`
      does not cover `priv/`.

      Module names are resolved through the lexical aliases in scope, so
      `alias MyApp.Repo, as: DB; DB.query!(...)`, `alias Ecto.Adapters.SQL;
      SQL.query!(...)`, and `alias Ash.Resource.Change; use Change` are
      all understood. The check does not compile anything, so a module
      that merely ends in `Repo` (`alias MyApp.Git.Repo`) is flagged too.
      Known limitations: imported repo functions
      (`import MyApp.Repo; query!(...)`) and calls through variables or
      module attributes (`@repo.query!(...)`) are not detected.
      """,
      params: [
        flagged_functions:
          "Repo functions to flag, as a list of atoms. Defaults to the functions " <>
            "that execute queries (`query`, `query!`, `query_many`, `query_many!`, " <>
            "`insert_all`, `update_all`, `delete_all`). Add `:insert`/`:update`/`:delete` " <>
            "to also flag single-record Ecto writes, or `:all`/`:one`/`:get`/`:get_by`/" <>
            "`:exists?`/`:aggregate` to flag reads, which bypass tenancy and policies " <>
            "too. Remove entries your team considers acceptable.",
        repo_names:
          "Last name segments to treat as Ecto repos. Atom entries match exactly; " <>
            "`Regex` entries (for example `~r/Repo$/`) match against the segment. " <>
            "Defaults to `[:Repo]`, the name almost every app uses. Add entries when " <>
            "your repos have other names, e.g. `[:Repo, :ReadReplica]`. Aliases are " <>
            "resolved first, so the match is on the real module name however the " <>
            "call is written. `Ecto.Adapters.SQL` is always checked, independent " <>
            "of this list.",
        excluded_paths:
          "Paths or regexes to skip. Binary entries match as path segments or full " <>
            "file paths. Defaults to test directories, where repo calls in fixture " <>
            "modules are intentional."
      ]
    ]

  alias AshCredo.Introspection.{Aliases, LexicalScopeWalker}
  alias AshCredo.{NameFilter, PathFilter}
  alias Credo.Code.Name

  @extension_points %{
    [:Ash, :Resource] => "Ash.Resource",
    [:Ash, :Resource, :Change] => "Ash.Resource.Change",
    [:Ash, :Resource, :Validation] => "Ash.Resource.Validation",
    [:Ash, :Resource, :Preparation] => "Ash.Resource.Preparation",
    [:Ash, :Resource, :Calculation] => "Ash.Resource.Calculation",
    [:Ash, :Resource, :Actions, :Implementation] => "Ash.Resource.Actions.Implementation"
  }

  @sql_adapter_segments [:Ecto, :Adapters, :SQL]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    excluded_paths = Params.get(params, :excluded_paths, __MODULE__)

    if PathFilter.excluded?(source_file.filename, excluded_paths) do
      []
    else
      issues_for_extension_points(source_file, params)
    end
  end

  defp issues_for_extension_points(source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    config = %{
      flagged:
        params |> Params.get(:flagged_functions, __MODULE__) |> List.wrap() |> MapSet.new(),
      repo_names: params |> Params.get(:repo_names, __MODULE__) |> List.wrap()
    }

    source_file
    |> repo_calls(config)
    |> Enum.map(fn {qualified, label, line} ->
      format_issue(issue_meta,
        message:
          "`#{qualified}` in an `#{label}` module can bypass the resource's tenant scoping, " <>
            "notifications, and timestamps, and skips policies for any rows beyond the " <>
            "one being acted on. Prefer an action via the code interface.",
        trigger: qualified,
        line_no: line
      )
    end)
  end

  # One lexical walk over the file. `labels` mirrors the walker's module
  # stack: each `defmodule` pushes `nil`, and a `use` of an extension
  # point resolved through the current env overwrites the head. A call
  # is gated by the innermost module only, so a plain helper module
  # nested in a resource is not blamed on the resource and a change
  # module nested in one is reported as a change. `quote` bodies are
  # skipped because that code runs where the macro is called.
  defp repo_calls(source_file, config) do
    {%{calls: calls}, _scope} =
      source_file
      |> Credo.SourceFile.ast()
      |> LexicalScopeWalker.traverse(
        %{labels: [], calls: []},
        &on_enter(&1, &2, &3, config),
        &on_leave/3
      )

    Enum.reverse(calls)
  end

  defp on_enter({:defmodule, _, _}, _scope, state, _config) do
    %{state | labels: [nil | state.labels]}
  end

  defp on_enter(
         {:use, _, [{:__aliases__, _, segments} | _]},
         scope,
         %{labels: [current | rest]} = state,
         _config
       )
       when is_list(segments) do
    if LexicalScopeWalker.in_quote?(scope) do
      state
    else
      resolved = Aliases.expand_alias(segments, LexicalScopeWalker.env(scope))
      %{state | labels: [Map.get(@extension_points, resolved, current) | rest]}
    end
  end

  defp on_enter(
         {{:., _, [{:__aliases__, _, segments}, fun]}, meta, args},
         scope,
         %{labels: [label | _]} = state,
         config
       )
       when is_binary(label) and is_atom(fun) and is_list(segments) and is_list(args) do
    if MapSet.member?(config.flagged, fun) and not LexicalScopeWalker.in_quote?(scope) and
         repo_module?(segments, scope, config.repo_names) do
      qualified = "#{Name.full(segments)}.#{fun}"
      %{state | calls: [{qualified, label, meta[:line]} | state.calls]}
    else
      state
    end
  end

  defp on_enter(_node, _scope, state, _config), do: state

  defp on_leave({:defmodule, _, _}, _scope, %{labels: [_ | rest]} = state) do
    %{state | labels: rest}
  end

  defp on_leave(_node, _scope, state), do: state

  # Every app names its own Ecto repo, so there is no fixed module to
  # match - but almost every app follows the `*.Repo` naming convention,
  # and `repo_names` covers the rest. The written segments are resolved
  # through the lexical env first, so `alias MyApp.Repo, as: DB` and
  # `alias Ecto.Adapters.SQL` both land on the real module, and
  # `__MODULE__.Repo` is substituted against the enclosing `defmodule`.
  defp repo_module?(segments, scope, repo_names) do
    resolved =
      segments
      |> Aliases.expand_alias(LexicalScopeWalker.env(scope))
      |> Aliases.resolve_module_self(LexicalScopeWalker.current_module_segments(scope))

    case resolved do
      {:ok, @sql_adapter_segments} -> true
      {:ok, resolved_segments} -> resolved_segments |> Enum.reverse() |> repo_name?(repo_names)
      :error -> false
    end
  end

  defp repo_name?([last | _], repo_names), do: NameFilter.matches_any?(last, repo_names)
end
