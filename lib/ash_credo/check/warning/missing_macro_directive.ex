defmodule AshCredo.Check.Warning.MissingMacroDirective do
  use AshCredo.CompiledCheck,
    base_priority: :high,
    category: :warning,
    tags: [:ash],
    param_defaults: [macro_modules: [Ash.Query, Ash.Expr]],
    explanations: [
      check: """
      Flags qualified calls to macros on configured modules (default
      `Ash.Query` and `Ash.Expr`) when no matching `require` or `import` of
      the macro module is lexically in scope at the call site.

      Several `Ash.Query` and `Ash.Expr` functions are actually macros:
      `Ash.Query.filter/2`, `equivalent_to/2`, `superset_of/2`, `subset_of/2`
      and their `?` variants, and `Ash.Expr.expr/1`, `where/2`, `or_where/2`,
      `calc/1..2`. Calling one of them without a matching `require` in scope
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

      Case #3 is the important one for a linter: the other two fail loudly
      at compile time, but this one ships to production if you miss the
      warning.

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

      `require` and `import` both satisfy the check: `import <Module>`
      implies `require <Module>` in Elixir, so qualified macro calls work
      after either directive.

      The check only inspects **qualified** remote calls
      (`Ash.Query.filter(...)`). Unqualified calls like `filter(...)` after
      `import Ash.Query` are out of scope: if the import is missing, Elixir
      raises a clear `undefined function filter/2` error at compile time,
      which is obvious enough to need no lint.

      The check accepts `require` and `import` in any lexical scope visible
      to the call: the module top, the enclosing `def` or `defp` body, or
      an enclosing `if`, `case`, or `with` branch. This matches Elixir's
      own scoping rules, so a directive in one function does not reach
      calls in a sibling function.

      The check tracks each configured module independently:
      `require Ash.Query` does **not** cover `Ash.Expr.expr(...)`, and vice
      versa. A module that uses macros from both modules needs both
      directives.

      The check deliberately ignores calls inside `quote do ... end`
      blocks. A macro author who writes `quote do Ash.Query.filter(...) end`
      is injecting the call into the caller's site, not emitting it from
      their own module, so flagging it would be a false positive.

      Nested `defmodule` blocks inherit `require`, `import`, and `alias`
      from the enclosing module the same way Elixir does, so an outer
      `require Ash.Query` (or `alias Ash.Query, as: Q`) applies to
      `Ash.Query.filter(...)` (or `Q.filter(...)`) inside a nested
      `defmodule`.

      The check is a **correctness backstop**: for projects without
      `--warnings-as-errors`, it converts the easy-to-miss runtime case
      (#3 above) into a lint issue. Style rules about *where* directives
      live are out of scope; if your team wants all directives at the
      module top, pair this check with
      `AshCredo.Check.Refactor.DirectiveInFunctionBody`.

      ## Precision

      The check uses compiled-BEAM introspection (`module.__info__(:macros)`)
      to learn which functions on each configured module are actually
      macros. This means:

        * It only flags real macro calls; it never flags a non-macro call
          on the same module (`Ash.Query.new/1`, for example).
        * New macros in future Ash releases are covered automatically,
          without code changes here.
        * User-supplied modules in `macro_modules` get the same precision
          as `Ash.Query` and `Ash.Expr`: only their real macros are
          flagged, not every qualified call.

      ## Requirements

      Compile your project before running `mix credo`. If Ash is not
      available in the VM running Credo, the check is a no-op and emits a
      single diagnostic. If a configured module cannot be loaded, the check
      emits a "could not load" diagnostic for that module and skips it for
      the run. The usual cause is adding one of your own modules to
      `macro_modules` without compiling first.

      ## Configuration

      `macro_modules` defaults to `[Ash.Query, Ash.Expr]`. Extend the list
      with any other macro modules your team uses:

          {AshCredo.Check.Warning.MissingMacroDirective,
           [macro_modules: [Ash.Query, Ash.Expr, MyApp.QueryMacros]]}
      """,
      params: [
        macro_modules:
          "Modules whose qualified macro calls the check validates. " <>
            "For each call to `<Module>.<macro>/n`, the check requires a " <>
            "`require` or `import` of `<Module>` lexically in scope: the " <>
            "module top, the enclosing `def` body, an enclosing branch, or " <>
            "a directive inherited from an enclosing `defmodule`. Defaults " <>
            "to `[Ash.Query, Ash.Expr]`. The exact set of macros on each " <>
            "module comes from compiled-BEAM introspection " <>
            "(`module.__info__(:macros)`), so the check only flags real " <>
            "macros and ignores regular functions on the same module."
      ]
    ]

  alias AshCredo.Introspection.{Aliases, LexicalScopeWalker}
  alias AshCredo.Introspection.Compiled, as: CompiledIntrospection

  @impl AshCredo.CompiledCheck
  def run_compiled(source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    targets = target_modules(params)

    do_run(source_file, targets, issue_meta)
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
      |> Enum.flat_map(fn {body, inherited_env} ->
        check_module_body(body, inherited_env, resolved, issue_meta)
      end)
      |> Enum.sort_by(& &1.line_no)

    load_issues ++ call_issues
  end

  # Resolves each configured module to its exact macro set via
  # `CompiledIntrospection.macros/1`. A module that fails to load
  # contributes one `:not_loadable` diagnostic (deduped across checks) and
  # is dropped from the resolved map, so we don't flag its call sites this
  # run. Returns `{resolved_map, load_issues}`.
  defp resolve_macro_sets(targets, issue_meta) do
    Enum.reduce(targets, {%{}, []}, &resolve_macro_set(&1, &2, issue_meta))
  end

  defp resolve_macro_set(mod, {resolved, issues}, issue_meta) do
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
  end

  # Walks the whole file AST and returns `{body, inherited_env}` tuples for
  # every `defmodule`, nested ones included. `inherited_env` is the
  # `Macro.Env` visible at the `defmodule` declaration; the walker records
  # `alias`/`require`/`import` directives into it, so nested modules
  # inherit all three from the enclosing lexical scope, exactly as Elixir
  # does. We do NOT capture defmodules inside `quote do ... end` blocks;
  # they belong to the macro caller's site.
  defp collect_module_bodies(ast) do
    {%{bodies: bodies}, _scope} =
      LexicalScopeWalker.traverse(
        ast,
        %{bodies: []},
        &enter_for_bodies/3,
        fn _node, _scope, acc -> acc end
      )

    Enum.reverse(bodies)
  end

  defp enter_for_bodies({:defmodule, _, [_alias, [do: body]]}, scope, state) do
    if LexicalScopeWalker.in_quote?(scope) do
      state
    else
      captured = {body, LexicalScopeWalker.env(scope)}
      %{state | bodies: [captured | state.bodies]}
    end
  end

  defp enter_for_bodies(_node, _scope, state), do: state

  # Single pass per body: walks the body with the inherited env as the base
  # frame, recording a site only when the env visible at that call site
  # does NOT require the call's module.
  defp check_module_body(body, inherited_env, resolved, issue_meta) do
    body
    |> collect_call_sites(inherited_env, resolved)
    |> Enum.map(&build_issue(&1, issue_meta))
  end

  # The body we traverse is already the contents of the outer `defmodule`'s
  # do-block; we never visit that outermost `{:do, body}` tuple ourselves,
  # so the walker's `:initial_env` opt seeds the inherited env into the
  # base frame. A nested module's calls then expand and resolve the same
  # way they do in Elixir.
  defp collect_call_sites(body, inherited_env, resolved) do
    {%{sites: sites}, _scope} =
      LexicalScopeWalker.traverse(
        body,
        %{sites: []},
        &enter_for_calls(&1, &2, &3, resolved),
        fn _node, _scope, acc -> acc end,
        initial_env: inherited_env
      )

    Enum.reverse(sites)
  end

  # A qualified remote call `Alias.fun(args)` parses as
  #   {{:., _, [{:__aliases__, _, segs}, fun]}, meta, args}
  # Expand `segs` through the env visible at the call, so `alias Ash.Query,
  # as: Q; Q.filter(...)` matches the same as a literal
  # `Ash.Query.filter(...)`. Skip calls inside a nested `defmodule` (we
  # process that body separately) or inside a `quote do ... end` block.
  defp enter_for_calls(
         {{:., _, [{:__aliases__, _, segs}, fun]}, meta, args},
         scope,
         state,
         resolved
       )
       when is_atom(fun) and is_list(args) do
    env = LexicalScopeWalker.env(scope)

    with false <- in_nested_module_or_quote?(scope),
         {:ok, mod} <- Aliases.expand_to_module(segs, env) do
      maybe_record_call(state, resolved, mod, fun, args, meta, env)
    else
      _ -> state
    end
  end

  defp enter_for_calls(_node, _scope, state, _resolved), do: state

  defp in_nested_module_or_quote?(scope) do
    # We use `in_module?/1`, not `current_module_segments != nil`, so we
    # also skip nested defmodules with non-literal names like
    # `defmodule Module.concat(...) do ... end`; those would otherwise be
    # processed as part of the outer module's call sites.
    LexicalScopeWalker.in_module?(scope) or LexicalScopeWalker.in_quote?(scope)
  end

  defp maybe_record_call(state, resolved, mod, fun, args, meta, env) do
    with {:ok, macros} <- Map.fetch(resolved, mod),
         true <- MapSet.member?(macros, fun),
         false <- Macro.Env.required?(env, mod) do
      site = %{module: mod, fun: fun, arity: length(args), line: meta[:line]}
      %{state | sites: [site | state.sites]}
    else
      _ -> state
    end
  end

  defp build_issue(site, issue_meta) do
    mod_str = inspect(site.module)
    trigger = "#{mod_str}.#{site.fun}"

    format_issue(issue_meta,
      message:
        "`#{trigger}/#{site.arity}` is a macro; add `require #{mod_str}` " <>
          "(or `import #{mod_str}`) somewhere lexically in scope - module top, " <>
          "the enclosing function body, or an enclosing block. Without it, " <>
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
