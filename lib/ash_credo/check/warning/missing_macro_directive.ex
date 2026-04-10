defmodule AshCredo.Check.Warning.MissingMacroDirective do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:ash],
    param_defaults: [macro_modules: [Ash.Query, Ash.Expr]],
    explanations: [
      check: """
      Flags qualified calls to macros on configured modules (default
      `Ash.Query` and `Ash.Expr`) when the enclosing module does not have a
      matching `require` or `import` at module level.

      Several `Ash.Query` and `Ash.Expr` functions are actually macros -
      `Ash.Query.filter/2`, `equivalent_to/2`, `superset_of/2`, `subset_of/2`
      and their `?` variants, and `Ash.Expr.expr/1`, `where/2`, `or_where/2`,
      `calc/1..2`. Calling any of them without a matching `require` in scope
      has three different failure modes, depending on the shape of the
      argument:

          # 1. Literal expression -> compile error with a misleading message
          Ash.Query.filter(Post, state == :published)
          # ** (CompileError) undefined variable "state"

          # 2. Pinned variable -> compile error about the pin operator
          Ash.Query.filter(Post, ^pre_built)
          # ** (CompileError) misplaced operator ^pre_built

          # 3. Bare variable holding a runtime value -> compiles with an
          # easy-to-miss warning, then fails at RUNTIME with
          # UndefinedFunctionError when the function is actually called.
          def foo(f), do: Ash.Query.filter(Post, f)
          # warning: Ash.Query.filter/2 is undefined or private...
          # ...later at runtime:
          # ** (UndefinedFunctionError) function Ash.Query.filter/2 is
          #    undefined or private

      Case #3 is the important one for a linter - the other two fail loudly
      at compile time, but this one ships to production if the warning is
      missed.

          # Flagged
          defmodule MyApp.PostQueries do
            def published do
              MyApp.Post
              |> Ash.Query.filter(state == :published)
              |> Ash.read!()
            end
          end

          # Preferred
          defmodule MyApp.PostQueries do
            require Ash.Query

            def published do
              MyApp.Post
              |> Ash.Query.filter(state == :published)
              |> Ash.read!()
            end
          end

      `require` and `import` both satisfy the check - `import <Module>`
      implies `require <Module>` in Elixir, so qualified macro calls work
      after either directive.

      Only **module-level** placement counts. A `require` inside a function
      body or any deeper block is lexically scoped and does not reach sibling
      functions or code outside its block. Rather than tracking lexical
      scope precisely, the check requires the directive to be a direct
      child of the `defmodule` do-block - the only placement that is a
      blanket guarantee for every call site in the module.

      Each configured module is tracked independently: `require Ash.Query`
      does **not** cover `Ash.Expr.expr(...)`, and vice versa. A module that
      uses macros from both modules needs both directives.

      Calls inside `quote do ... end` blocks are deliberately ignored. A
      macro author who writes `quote do Ash.Query.filter(...) end` is
      injecting the call into the caller's site, not emitting it from their
      own module, so flagging it would be a false positive.

      Nested `defmodule` blocks do not inherit each other's directives.
      Each module is checked against its own module-level requires.

      ## Precision

      The check uses compiled-BEAM introspection (`module.__info__(:macros)`)
      to learn which functions on each configured module are actually
      macros. This means:

        * It only flags real macro calls - non-macro calls on the same
          module (`Ash.Query.new/1`, for example) are never flagged.
        * New macros added in future Ash releases are automatically picked
          up without code changes here.
        * User-supplied modules in `macro_modules` are handled with the same
          precision as `Ash.Query`/`Ash.Expr` - only their actual macros
          are flagged, not every qualified call.

      ## Known limitations

      * **Aliased modules.** `alias Ash.Query, as: Q` followed by
        `Q.filter(...)` is not detected. The check matches the exact
        module alias path in the AST.

      ## Requirements

      Your project must be compiled before running `mix credo`. If Ash is
      not available in the VM running Credo, the check is a no-op and emits
      a single diagnostic. If a configured module cannot be loaded (typical
      cause: you added one of your own modules to `macro_modules` and have
      not compiled yet), the check emits a per-module "could not load"
      diagnostic and skips that module for the run.

      ## Configuration

      `macro_modules` defaults to `[Ash.Query, Ash.Expr]`. Extend the list
      with additional macro modules your team uses:

          {AshCredo.Check.Warning.MissingMacroDirective,
           [macro_modules: [Ash.Query, Ash.Expr, MyApp.QueryMacros]]}
      """,
      params: [
        macro_modules:
          "List of modules whose qualified macro calls require a matching " <>
            "module-level `require` or `import`. Defaults to `[Ash.Query, " <>
            "Ash.Expr]`. The exact set of macros on each module is read " <>
            "from compiled-BEAM introspection, so only real macros are " <>
            "flagged - regular functions on the same module are ignored."
      ]
    ]

  alias AshCredo.Introspection.Compiled, as: CompiledIntrospection

  @directive_kinds ~w(require import)a

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    targets = target_modules(params)

    CompiledIntrospection.with_compiled_check(
      fn ->
        format_issue(issue_meta,
          message:
            "Ash is not loaded in the VM running Credo - `MissingMacroDirective` " <>
              "is a no-op. Add `:ash` as a dependency, or disable this check " <>
              "in `.credo.exs`.",
          line_no: 1
        )
      end,
      fn -> do_run(source_file, targets, issue_meta) end
    )
  end

  defp target_modules(params) do
    params
    |> Params.get(:macro_modules, __MODULE__)
    |> List.wrap()
  end

  defp do_run(source_file, targets, issue_meta) do
    {resolved, load_issues} = resolve_macro_sets(targets, issue_meta)

    call_issues =
      source_file
      |> Credo.SourceFile.ast()
      |> collect_module_bodies()
      |> Enum.flat_map(&check_module_body(&1, resolved, issue_meta))
      |> Enum.sort_by(& &1.line_no)

    load_issues ++ call_issues
  end

  # Resolves each configured module to its exact macro set via
  # `CompiledIntrospection.macros/1`. Modules that fail to load contribute
  # a per-module `:not_loadable` diagnostic (deduped across checks) and are
  # dropped from the resolved map so their call sites aren't flagged this
  # run. Returns `{resolved_map, load_issues}`.
  defp resolve_macro_sets(targets, issue_meta) do
    Enum.reduce(targets, {%{}, []}, fn mod, {resolved, issues} ->
      case CompiledIntrospection.macros(mod) do
        {:ok, macros} ->
          {Map.put(resolved, mod, macros), issues}

        {:error, :not_loadable} ->
          extra =
            CompiledIntrospection.with_unique_not_loadable(mod, fn ->
              not_loadable_issue(mod, issue_meta)
            end)

          {resolved, extra ++ issues}
      end
    end)
  end

  # Walks the whole file AST and returns the do-block body of every
  # `defmodule` encountered (including nested ones). Each returned body is
  # later analyzed independently.
  defp collect_module_bodies(ast) do
    {_, bodies} =
      Macro.prewalk(ast, [], fn
        {:defmodule, _, [_alias, [do: body]]} = node, acc ->
          {node, [body | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(bodies)
  end

  # For one module body, collect:
  #   * the set of target modules required/imported at the module's top level
  #   * every qualified call to a target-module macro inside this module
  #     (but NOT inside any nested defmodule or inside a quote block)
  # and emit an issue for every call whose target module is not in the
  # top-level directive set.
  defp check_module_body(body, resolved, issue_meta) do
    target_keys = resolved |> Map.keys() |> MapSet.new()
    top_level_requires = collect_top_level_directives(body, target_keys)
    call_sites = collect_call_sites(body, resolved)

    Enum.flat_map(call_sites, fn site ->
      if MapSet.member?(top_level_requires, site.module) do
        []
      else
        [build_issue(site, issue_meta)]
      end
    end)
  end

  # Module-level statements are the direct children of the defmodule do-block.
  # The body is either a `__block__` wrapping several statements or a single
  # statement. We only inspect that outermost layer - directives further down
  # (inside a function, inside an `if`, inside `actions do ...`) are not
  # module-level and do not count.
  defp collect_top_level_directives({:__block__, _, stmts}, targets) do
    collect_top_level_directives_from(stmts, targets)
  end

  defp collect_top_level_directives(stmt, targets) do
    collect_top_level_directives_from([stmt], targets)
  end

  defp collect_top_level_directives_from(stmts, targets) do
    Enum.reduce(stmts, MapSet.new(), fn stmt, acc ->
      case stmt do
        {directive, _, [{:__aliases__, _, segs} | _]}
        when directive in @directive_kinds ->
          with true <- Enum.all?(segs, &is_atom/1),
               mod = Module.concat(segs),
               true <- MapSet.member?(targets, mod) do
            MapSet.put(acc, mod)
          else
            _ -> acc
          end

        _ ->
          acc
      end
    end)
  end

  defp collect_call_sites(body, resolved) do
    {_ast, %{sites: sites}} =
      Macro.traverse(
        body,
        %{defmodule_depth: 0, quote_depth: 0, sites: []},
        &enter_for_calls(&1, &2, resolved),
        &leave_for_calls/2
      )

    Enum.reverse(sites)
  end

  # Skip into a nested defmodule - its contents belong to the inner module,
  # and will be processed on its own pass via `collect_module_bodies/1`.
  defp enter_for_calls({:defmodule, _, _} = node, state, _resolved) do
    {node, %{state | defmodule_depth: state.defmodule_depth + 1}}
  end

  # Skip into `quote do ... end` - any calls inside are generated code and
  # belong to the macro caller's site, not here.
  defp enter_for_calls({:quote, _, _} = node, state, _resolved) do
    {node, %{state | quote_depth: state.quote_depth + 1}}
  end

  # Qualified remote call: `Alias.fun(args)` parses as
  #   {{:., _, [{:__aliases__, _, segs}, fun}]}, meta, args}
  defp enter_for_calls(
         {{:., _, [{:__aliases__, _, segs}, fun]}, meta, args} = node,
         state,
         resolved
       )
       when is_atom(fun) and is_list(args) do
    if state.defmodule_depth == 0 and state.quote_depth == 0 and
         Enum.all?(segs, &is_atom/1) do
      mod = Module.concat(segs)

      case Map.fetch(resolved, mod) do
        {:ok, macros} ->
          if MapSet.member?(macros, fun) do
            site = %{module: mod, fun: fun, arity: length(args), line: meta[:line]}
            {node, %{state | sites: [site | state.sites]}}
          else
            {node, state}
          end

        :error ->
          {node, state}
      end
    else
      {node, state}
    end
  end

  defp enter_for_calls(node, state, _resolved), do: {node, state}

  defp leave_for_calls({:defmodule, _, _} = node, state) do
    {node, %{state | defmodule_depth: max(state.defmodule_depth - 1, 0)}}
  end

  defp leave_for_calls({:quote, _, _} = node, state) do
    {node, %{state | quote_depth: max(state.quote_depth - 1, 0)}}
  end

  defp leave_for_calls(node, state), do: {node, state}

  defp build_issue(site, issue_meta) do
    mod_str = inspect(site.module)
    trigger = "#{mod_str}.#{site.fun}"

    format_issue(issue_meta,
      message:
        "`#{trigger}/#{site.arity}` is a macro; add `require #{mod_str}` " <>
          "(or `import #{mod_str}`) at the top of this module. Without it, " <>
          "Elixir reports a cryptic `undefined variable` / `misplaced ^` " <>
          "compile error, or - if the argument is a runtime value - compiles " <>
          "and fails at runtime with `UndefinedFunctionError`.",
      trigger: trigger,
      line_no: site.line
    )
  end

  defp not_loadable_issue(module, issue_meta) do
    format_issue(issue_meta,
      message:
        "Could not load `#{inspect(module)}` for `MissingMacroDirective`. " <>
          "Run `mix compile` before `mix credo`, remove it from " <>
          "`macro_modules`, or disable this check in `.credo.exs`.",
      line_no: 1
    )
  end
end
