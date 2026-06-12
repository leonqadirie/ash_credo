defmodule AshCredo.Check.Refactor.RaisingCall do
  use Credo.Check,
    base_priority: :low,
    category: :refactor,
    tags: [:ash],
    param_defaults: [
      excluded_functions: [],
      excluded_paths: [~r"/test/", "test"],
      flag_bang_only_apis: false
    ],
    explanations: [
      check: """
      Flags Ash bang calls that raise on `{:error, _}` instead of returning
      `{:ok, _} | {:error, _}` tuples - awkward in code paths that need to
      translate Ash errors into HTTP responses, GraphQL payloads, or
      job-runner outcomes.

          # Flagged
          posts = Ash.read!(MyApp.Post)

          # Preferred
          case Ash.read(MyApp.Post) do
            {:ok, posts} -> ...
            {:error, error} -> ...
          end

      Requires the host project to be compiled with Ash loaded - same
      contract as `UseCodeInterface`, `MissingCodeInterface`, etc. When
      Ash isn't loadable the check emits one `:ash_missing` diagnostic
      and becomes a no-op.

      Two detectors run when the gate passes:

      1. **`Ash.*!` bangs** - top-level (`Ash.read!`, `Ash.create!`) and
         nested (`Ash.Filter.parse!`, `Ash.Expr.eval!`).

      2. **Code-interface bangs** - `MyApp.Blog.create_post!` from a
         domain's `code_interface`, or `MyApp.Blog.Post.create_post!`
         from a resource's `code_interface`, including calculation
         interfaces. Confirmed against `Ash.Resource.Info` /
         `Ash.Domain.Info` - calls to non-Ash modules are silently
         skipped, as are user modules that aren't yet compiled (they'd
         be indistinguishable from arbitrary third-party bangs).

      Bang-only APIs - bangs that have no non-bang counterpart, like
      `Ash.stream!` or `Ash.Seed.seed!` - are skipped by default. Probing
      `module.__info__(:functions)` for the trimmed-`!` name tells us
      the suggested replacement wouldn't exist, so a default suggestion
      would name a nonexistent function. To surface these calls anyway
      under a generic "ensure failures are handled" message, opt in
      with `flag_bang_only_apis: true`. Calls passing `stream?: true`
      to a read code-interface are also silently skipped, because the
      non-bang variant rejects streaming.

      The "Prefer `Mod.fun`" suggestion is worded based on the non-bang
      counterpart's typespec: tuple-returning APIs (`Ash.read`,
      `Ash.create`, ...) get the "match on `{:ok, _} | {:error, _}`"
      message, while helpers whose non-bang twin returns something else
      (e.g. `Ash.Resource.Info.primary_action/2` returns `action | nil`)
      get a conservative "handle the returned value explicitly" message.

      Use `excluded_functions` to silence specific bangs by
      `{module, :fun!}` tuple:

          excluded_functions: [
            {MyApp.Blog, :archive_all_posts!}
          ]

      Test directories are excluded by default since bang versions in tests
      are idiomatic ("crash loudly on unexpected errors"). Override
      `excluded_paths` (e.g. to `[]`) if you want to flag bang calls in
      tests too. Entries can be path segments (`"test"` excludes any file
      under a `test/` directory) or full file paths
      (`"priv/seeds.exs"` excludes that exact file).

      Both detectors resolve aliases lexically. The common
      `alias __MODULE__.Foo` pattern is resolved using the enclosing
      `defmodule`, so `Foo.archive!()` and `MyApp.Blog.Foo.archive!()`
      are treated identically. Unsupported call shapes that can never be
      flagged: `apply/3`, variable modules (`mod.fun!()`), macro-generated
      bang names, and bare `__MODULE__.fun!()` (no alias).
      """,
      params: [
        excluded_functions:
          "Bang functions to allow without flagging, given as `{module, :fun!}` tuples. Defaults to `[]` - bang-only APIs (those with no non-bang counterpart) are detected dynamically via `module.__info__(:functions)`, so no curated allowlist is needed.",
        excluded_paths:
          "Paths or regexes to skip. Defaults to test directories, where bang versions are idiomatic.",
        flag_bang_only_apis:
          "When `true`, also flag bangs that have no non-bang counterpart (e.g. `Ash.stream!`, `Ash.Seed.seed!`) with a generic 'ensure failures are handled' message. Defaults to `false` because the suggested non-bang twin doesn't exist for these calls; opt in only if your team policy is 'no bare bang calls'."
      ]
    ]

  alias AshCredo.{Cache, Orchestration, PathFilter}
  alias AshCredo.Introspection.{AshCallScanner, RemoteBangScanner}
  alias AshCredo.Introspection.Compiled, as: CompiledIntrospection

  @counterpart_key_tag {__MODULE__, :counterpart}

  @impl true
  def run(%SourceFile{} = source_file, params) do
    excluded_paths = Params.get(params, :excluded_paths, __MODULE__)

    if PathFilter.excluded?(source_file.filename, excluded_paths) do
      []
    else
      excluded_functions =
        params
        |> Params.get(:excluded_functions, __MODULE__)
        |> MapSet.new()

      flag_bang_only = Params.get(params, :flag_bang_only_apis, __MODULE__)
      issue_meta = IssueMeta.for(source_file, params)

      CompiledIntrospection.with_compiled_check(
        fn -> Orchestration.ash_missing_issue(issue_meta, __MODULE__) end,
        fn ->
          ash_bang_issues(source_file, excluded_functions, flag_bang_only, issue_meta) ++
            code_interface_issues(source_file, excluded_functions, issue_meta)
        end
      )
    end
  end

  defp ash_bang_issues(source_file, excluded_functions, flag_bang_only, issue_meta) do
    source_file
    |> AshCallScanner.calls_with_module()
    |> Enum.flat_map(&check_ash_call(&1, excluded_functions, flag_bang_only, issue_meta))
  end

  defp code_interface_issues(source_file, excluded_functions, issue_meta) do
    source_file
    |> RemoteBangScanner.calls()
    |> Enum.flat_map(&check_code_interface_call(&1, excluded_functions, issue_meta))
  end

  defp check_ash_call({call_ast, expanded_module}, excluded_functions, flag_bang_only, issue_meta) do
    case call_ast do
      {{:., _, [module_ast, fun_name]}, meta, _args}
      when is_atom(fun_name) and is_list(meta) ->
        module = Module.concat(expanded_module)

        cond do
          not bang?(fun_name) ->
            []

          MapSet.member?(excluded_functions, {module, fun_name}) ->
            []

          true ->
            ash_call_issues(
              non_bang_counterpart(module, fun_name),
              module_ast,
              expanded_module,
              fun_name,
              meta,
              flag_bang_only,
              issue_meta
            )
        end

      _ ->
        []
    end
  end

  defp ash_call_issues(:has_tuple, module_ast, expanded, fun, meta, _flag_bang_only, issue_meta) do
    [bang_issue(:syntactic_tuple, module_ast, expanded, fun, meta, issue_meta)]
  end

  defp ash_call_issues(
         :has_non_tuple,
         module_ast,
         expanded,
         fun,
         meta,
         _flag_bang_only,
         issue_meta
       ) do
    [bang_issue(:syntactic_generic, module_ast, expanded, fun, meta, issue_meta)]
  end

  defp ash_call_issues(:no_counterpart, module_ast, expanded, fun, meta, true, issue_meta) do
    [bang_issue(:bang_only, module_ast, expanded, fun, meta, issue_meta)]
  end

  # `:no_counterpart` with `flag_bang_only_apis: false`, and `:not_loadable`
  # (typo'd `Ash.NoSuchMod.fun!`, or an alias-expanded path that doesn't
  # resolve to a real module): better to stay silent than emit a "Prefer
  # `Mod.fun`" suggestion that names a function we know - or can't tell -
  # doesn't exist.
  defp ash_call_issues(_kind, _module_ast, _expanded, _fun, _meta, _flag_bang_only, _issue_meta) do
    []
  end

  defp check_code_interface_call(
         {call_ast, expanded_module, fun_name},
         excluded_functions,
         issue_meta
       ) do
    case call_ast do
      {{:., _, [module_ast, ^fun_name]}, meta, args}
      when is_list(args) and is_list(meta) ->
        module = Module.concat(expanded_module)

        if eligible_for_interface_check?(expanded_module, module, fun_name, excluded_functions) do
          maybe_code_interface_issue(
            module,
            module_ast,
            expanded_module,
            fun_name,
            meta,
            args,
            issue_meta
          )
        else
          []
        end

      _ ->
        []
    end
  end

  defp eligible_for_interface_check?(expanded_module, module, fun_name, excluded_functions) do
    not ash_namespace?(expanded_module) and
      not MapSet.member?(excluded_functions, {module, fun_name})
  end

  defp maybe_code_interface_issue(
         module,
         module_ast,
         expanded_module,
         fun_name,
         meta,
         args,
         issue_meta
       ) do
    case CompiledIntrospection.code_interface_bang(module, fun_name) do
      {:ok, info} ->
        if stream_opt?(args) and read_interface?(info) do
          []
        else
          [bang_issue(:code_interface, module_ast, expanded_module, fun_name, meta, issue_meta)]
        end

      {:error, _} ->
        []
    end
  end

  # `stream?: true` is only meaningful on read interfaces - the non-bang
  # variant of a read code-interface rejects streaming, so suggesting it
  # would be wrong advice. On write or calculation interfaces, `stream?`
  # is not a recognised option and the bang should still be flagged.
  defp read_interface?(%{interface: iface, resource: resource}) when is_atom(resource) do
    case Map.get(iface, :action) || Map.get(iface, :name) do
      action_name when is_atom(action_name) ->
        match?({:ok, %{type: :read}}, CompiledIntrospection.action(resource, action_name))

      _ ->
        false
    end
  end

  defp read_interface?(_), do: false

  defp ash_namespace?([:Ash | _]), do: true
  defp ash_namespace?(_), do: false

  defp bang?(fun_name) do
    fun_name
    |> Atom.to_string()
    |> String.ends_with?("!")
  end

  # Resolves the non-bang counterpart's existence AND return shape:
  #
  #   * `:has_tuple`      - a same-named non-bang twin exists and its
  #     typespec returns `{:ok, _} | {:error, _}` (proven by walking the
  #     spec's union for a literal `:ok` tuple). Caller emits the tuple-
  #     specific "match on `{:ok, _} | {:error, _}`" suggestion.
  #   * `:has_non_tuple`  - twin exists but the typespec proves something
  #     else (e.g. `Ash.Resource.Info.primary_action/2` returns
  #     `action | nil`), OR no spec is available. Caller emits the
  #     conservative "handle the returned value explicitly" suggestion -
  #     correct advice without lying about tuple semantics.
  #   * `:no_counterpart` - module loaded but exports no matching non-bang
  #     twin (`Ash.stream!`, `Ash.Seed.seed!`, ...). Caller emits the
  #     generic bang-only message when `flag_bang_only_apis: true`,
  #     otherwise skips.
  #   * `:not_loadable`   - `Code.ensure_loaded/1` failed (typo'd
  #     `Ash.NoSuchSubmod.fun!`, alias-expanded path that resolves to a
  #     nonexistent module). Caller skips silently rather than emitting a
  #     suggestion that names a function we can't confirm exists.
  defp non_bang_counterpart(module, bang_name) do
    case Cache.get({@counterpart_key_tag, module, bang_name}, :miss) do
      :miss ->
        result = compute_counterpart(module, bang_name)
        Cache.put({@counterpart_key_tag, module, bang_name}, result)
        result

      cached ->
        cached
    end
  end

  defp compute_counterpart(module, bang_name) do
    case Code.ensure_loaded(module) do
      {:module, ^module} -> counterpart_state(module, bang_name)
      _ -> :not_loadable
    end
  end

  defp counterpart_state(module, bang_name) do
    target = bang_name |> Atom.to_string() |> String.trim_trailing("!")
    exports = module.__info__(:functions) ++ module.__info__(:macros)

    case Enum.find(exports, fn {n, _} -> Atom.to_string(n) == target end) do
      nil -> :no_counterpart
      {non_bang, _} -> if tuple_returning?(module, non_bang), do: :has_tuple, else: :has_non_tuple
    end
  end

  # Considers a function tuple-returning if any of its specs (any arity)
  # declares a return type whose union contains a literal `{:ok, _}` tuple.
  # Heuristic - it deliberately does NOT chase type aliases, so a function
  # whose spec returns `Mod.tuple_result()` classifies as non-tuple even
  # if the alias expands to `{:ok, _} | {:error, _}`. That misses some
  # tuple APIs but never lies about tuple semantics, which is the goal.
  defp tuple_returning?(module, name) do
    case Code.Typespec.fetch_specs(module) do
      {:ok, all_specs} ->
        all_specs
        |> Enum.flat_map(fn
          {{^name, _arity}, asts} -> asts
          _ -> []
        end)
        |> Enum.any?(&spec_returns_ok_tuple?/1)

      :error ->
        false
    end
  end

  defp spec_returns_ok_tuple?({:type, _, :fun, [_args, return]}), do: contains_ok_tuple?(return)

  defp spec_returns_ok_tuple?({:type, _, :bounded_fun, [fun_spec, _]}),
    do: spec_returns_ok_tuple?(fun_spec)

  defp spec_returns_ok_tuple?(_), do: false

  defp contains_ok_tuple?({:type, _, :tuple, [{:atom, _, :ok} | _]}), do: true
  defp contains_ok_tuple?({:type, _, :union, types}), do: Enum.any?(types, &contains_ok_tuple?/1)
  defp contains_ok_tuple?({:ann_type, _, [_name, type]}), do: contains_ok_tuple?(type)
  defp contains_ok_tuple?(_), do: false

  # Detects `stream?: true` anywhere in the call's top-level keyword args.
  # Callers gate the skip on `read_interface?/1` so writes and calculations
  # (where `stream?: true` is meaningless or simply ignored) still flag.
  defp stream_opt?(args) do
    Enum.any?(args, fn
      kw when is_list(kw) -> Keyword.get(kw, :stream?) == true
      _ -> false
    end)
  end

  defp bang_issue(kind, module_ast, expanded_module, fun_name, meta, issue_meta) do
    source_module_str = source_module_string(module_ast, expanded_module)
    canonical_module_str = module_string(expanded_module)
    fun_str = Atom.to_string(fun_name)
    trigger = "#{source_module_str}.#{fun_str}"
    canonical_qualified = "#{canonical_module_str}.#{fun_str}"

    format_issue(issue_meta,
      message: message(kind, canonical_module_str, fun_str, canonical_qualified),
      trigger: trigger,
      line_no: meta[:line]
    )
  end

  defp message(:syntactic_tuple, module_str, fun_str, qualified) do
    non_bang = String.trim_trailing(fun_str, "!")

    "Prefer `#{module_str}.#{non_bang}` and handle the `{:ok, _} | {:error, _}` tuple explicitly. " <>
      "`#{qualified}` raises on errors, which can crash callers expecting tuple results."
  end

  defp message(:syntactic_generic, module_str, fun_str, qualified) do
    non_bang = String.trim_trailing(fun_str, "!")

    "Prefer `#{module_str}.#{non_bang}` and handle the returned value explicitly. " <>
      "`#{qualified}` raises on errors, which can crash callers."
  end

  defp message(:code_interface, module_str, fun_str, qualified) do
    non_bang = String.trim_trailing(fun_str, "!")

    "Prefer `#{module_str}.#{non_bang}` and handle the `{:ok, _} | {:error, _}` tuple explicitly. " <>
      "`#{qualified}` is an Ash code-interface bang that raises on errors."
  end

  defp message(:bang_only, _module_str, _fun_str, qualified) do
    "`#{qualified}` has no non-bang counterpart and will raise on errors. " <>
      "Ensure failures are properly handled at the call site."
  end

  defp source_module_string({:__aliases__, _, segments}, _expanded) when is_list(segments) do
    Enum.map_join(segments, ".", &Atom.to_string/1)
  end

  defp source_module_string(_module_ast, expanded), do: module_string(expanded)

  defp module_string(segments), do: Enum.map_join(segments, ".", &Atom.to_string/1)
end
