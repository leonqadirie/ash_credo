defmodule AshCredo.Check.Warning.MissingMacroDirective do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:ash],
    param_defaults: [macro_modules: [Ash.Query, Ash.Expr]],
    explanations: [
      check: """
      Flags qualified calls to macros on configured modules (default
      `Ash.Query` and `Ash.Expr`) when no matching `require` or `import` of
      the macro module is lexically in scope at the call site.

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

      Only **qualified** remote calls (`Ash.Query.filter(...)`) are
      inspected. Unqualified calls like `filter(...)` after `import Ash.Query`
      are out of scope: if the import is missing, Elixir raises a clean
      `undefined function filter/2` at compile time, which is obvious enough
      to need no lint.

      `require`/`import` are accepted in any lexical scope visible to the
      call - module top, the enclosing `def`/`defp` body, an enclosing
      `if`/`case`/`with` branch, etc. - matching Elixir's own scoping rules.
      A directive in one function does not reach calls in a sibling function.

      Each configured module is tracked independently: `require Ash.Query`
      does **not** cover `Ash.Expr.expr(...)`, and vice versa. A module that
      uses macros from both modules needs both directives.

      Calls inside `quote do ... end` blocks are deliberately ignored. A
      macro author who writes `quote do Ash.Query.filter(...) end` is
      injecting the call into the caller's site, not emitting it from their
      own module, so flagging it would be a false positive.

      Nested `defmodule` blocks inherit `require`/`import` and `alias` from
      the enclosing module the same way Elixir does, so an outer
      `require Ash.Query` (or `alias Ash.Query, as: Q`) is honored by
      `Ash.Query.filter(...)` (or `Q.filter(...)`) inside a nested `defmodule`.

      This check is a **correctness backstop**: for projects without
      `--warnings-as-errors`, it converts the easy-to-miss runtime case
      (#3 above) into a lint issue. Style rules about *where* directives
      live are out of scope; pair with `AshCredo.Check.Refactor.DirectiveInFunctionBody`
      if your team wants to centralise directives at module top.

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
          "List of modules whose qualified macro calls the check validates. " <>
            "For each call to `<Module>.<macro>/n` the check requires a " <>
            "`require` or `import` of `<Module>` to be lexically in scope - " <>
            "module top, the enclosing `def` body, an enclosing branch, or " <>
            "inherited from an enclosing `defmodule`. Defaults to " <>
            "`[Ash.Query, Ash.Expr]`. The exact set of macros on each " <>
            "module is read from compiled-BEAM introspection " <>
            "(`module.__info__(:macros)`), so only real macros are flagged - " <>
            "regular functions on the same module are ignored."
      ]
    ]

  alias AshCredo.Introspection.{Aliases, LexicalScopeWalker}
  alias AshCredo.Introspection.Compiled, as: CompiledIntrospection

  @directive_kinds ~w(require import)a
  # Constructs whose clauses/generators evaluate in their own block-level
  # scope (verified empirically: a `require` written inside a `with` clause
  # or a `for` generator does NOT propagate to expressions after the
  # construct). `if` conditions and `case` subjects, by contrast, evaluate
  # in the outer scope and leak - so they are deliberately not listed here.
  @construct_scope_nodes ~w(with for)a

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
    target_keys = resolved |> Map.keys() |> MapSet.new()

    call_issues =
      source_file
      |> Credo.SourceFile.ast()
      |> collect_module_bodies(target_keys)
      |> Enum.flat_map(fn {body, inherited_aliases, inherited_required} ->
        check_module_body(
          body,
          inherited_aliases,
          inherited_required,
          resolved,
          target_keys,
          issue_meta
        )
      end)
      |> Enum.sort_by(& &1.line_no)

    load_issues ++ call_issues
  end

  # Resolves each configured module to its exact macro set via
  # `CompiledIntrospection.macros/1`. Modules that fail to load contribute
  # a per-module `:not_loadable` diagnostic (deduped across checks) and are
  # dropped from the resolved map so their call sites aren't flagged this
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

  # Walks the whole file AST and returns `{body, inherited_aliases,
  # inherited_required}` tuples for every `defmodule` (including nested ones).
  # `inherited_aliases` and `inherited_required` are the aliases and required
  # target modules visible at the point of the `defmodule` declaration - in
  # Elixir, nested modules inherit both `alias` and `require`/`import` from
  # the enclosing lexical scope. Defmodules inside `quote do ... end` are
  # NOT captured (they belong to the macro caller's site).
  defp collect_module_bodies(ast, target_keys) do
    initial_state = %{
      require_frames: [MapSet.new()],
      target_keys: target_keys,
      bodies: []
    }

    {%{bodies: bodies}, _scope} =
      LexicalScopeWalker.traverse(
        ast,
        initial_state,
        &enter_for_bodies/3,
        fn _node, _scope, acc -> acc end,
        lexical_scope_nodes: @construct_scope_nodes,
        on_frame_push: &push_require_frame/1,
        on_frame_pop: &pop_require_frame/1
      )

    Enum.reverse(bodies)
  end

  defp enter_for_bodies({directive, _, [{:__aliases__, _, segs} | _]}, scope, state)
       when directive in @directive_kinds do
    if LexicalScopeWalker.in_quote?(scope) do
      state
    else
      maybe_put_required(state, segs, scope)
    end
  end

  defp enter_for_bodies({:defmodule, _, [_alias, [do: body]]}, scope, state) do
    if LexicalScopeWalker.in_quote?(scope) do
      state
    else
      captured = {body, LexicalScopeWalker.aliases(scope), current_required(state)}
      %{state | bodies: [captured | state.bodies]}
    end
  end

  defp enter_for_bodies(_node, _scope, state), do: state

  # Single-pass per-body check: walks the body tracking lexical alias and
  # require/import frames, and records sites only when the call's module is
  # NOT in the require scope visible at that call site.
  defp check_module_body(
         body,
         inherited_aliases,
         inherited_required,
         resolved,
         target_keys,
         issue_meta
       ) do
    body
    |> collect_call_sites(inherited_aliases, inherited_required, resolved, target_keys)
    |> Enum.map(&build_issue(&1, issue_meta))
  end

  # Walks `segs` once: returns `{:ok, Module.concat(segs)}` only if every
  # segment is an atom (rejecting interpolated/quoted aliases like
  # `unquote(mod)` or `__MODULE__` mid-segment), otherwise `:error`.
  defp atomic_module(segs) do
    segs
    |> Enum.reduce_while([], fn
      seg, acc when is_atom(seg) -> {:cont, [seg | acc]}
      _seg, _acc -> {:halt, :error}
    end)
    |> case do
      :error -> :error
      reversed -> {:ok, reversed |> Enum.reverse() |> Module.concat()}
    end
  end

  # The body we traverse is already the contents of the enclosing `defmodule`'s
  # do-block - we never visit that outermost `{:do, body}` tuple ourselves, so
  # we rely on the walker's `:initial_aliases` opt to seed inherited aliases
  # into the base frame, and we seed `require_frames` with the inherited
  # required set in `initial_state` below. A nested module's calls then
  # expand and resolve the same way Elixir does.
  defp collect_call_sites(body, inherited_aliases, inherited_required, resolved, target_keys) do
    initial_state = %{
      require_frames: [inherited_required],
      target_keys: target_keys,
      sites: []
    }

    {%{sites: sites}, _scope} =
      LexicalScopeWalker.traverse(
        body,
        initial_state,
        &enter_for_calls(&1, &2, &3, resolved),
        fn _node, _scope, acc -> acc end,
        track_module_stack: true,
        lexical_scope_nodes: @construct_scope_nodes,
        initial_aliases: inherited_aliases,
        on_frame_push: &push_require_frame/1,
        on_frame_pop: &pop_require_frame/1
      )

    Enum.reverse(sites)
  end

  defp enter_for_calls({directive, _, [{:__aliases__, _, segs} | _]}, scope, state, _resolved)
       when directive in @directive_kinds do
    if LexicalScopeWalker.in_quote?(scope) do
      state
    else
      maybe_put_required(state, segs, scope)
    end
  end

  # Qualified remote call: `Alias.fun(args)` parses as
  #   {{:., _, [{:__aliases__, _, segs}, fun}]}, meta, args}
  # Expand `segs` against the visible alias frames so `alias Ash.Query, as: Q;
  # Q.filter(...)` is matched the same as a literal `Ash.Query.filter(...)`.
  # Skip when inside a nested `defmodule` (that body is processed separately)
  # or inside a `quote do ... end`.
  defp enter_for_calls(
         {{:., _, [{:__aliases__, _, segs}, fun]}, meta, args},
         scope,
         state,
         resolved
       )
       when is_atom(fun) and is_list(args) do
    with false <- in_nested_module_or_quote?(scope),
         {:ok, mod} <-
           atomic_module(Aliases.expand_alias(segs, LexicalScopeWalker.aliases(scope))) do
      maybe_record_call(state, resolved, mod, fun, args, meta)
    else
      _ -> state
    end
  end

  defp enter_for_calls(_node, _scope, state, _resolved), do: state

  defp in_nested_module_or_quote?(scope) do
    # `in_module?/1` (not `current_module_segments != nil`) so we also skip
    # into nested defmodules with non-literal names like
    # `defmodule Module.concat(...) do ... end` - those would otherwise be
    # processed as part of the outer module's call sites.
    LexicalScopeWalker.in_module?(scope) or LexicalScopeWalker.in_quote?(scope)
  end

  defp maybe_record_call(state, resolved, mod, fun, args, meta) do
    with {:ok, macros} <- Map.fetch(resolved, mod),
         true <- MapSet.member?(macros, fun),
         false <- MapSet.member?(current_required(state), mod) do
      site = %{module: mod, fun: fun, arity: length(args), line: meta[:line]}
      %{state | sites: [site | state.sites]}
    else
      _ -> state
    end
  end

  defp push_require_frame(state), do: update_in(state.require_frames, &[MapSet.new() | &1])

  defp pop_require_frame(%{require_frames: [_ | rest]} = state),
    do: %{state | require_frames: rest}

  defp pop_require_frame(state), do: state

  # Resolve `segs` against the visible alias frames, then add to the current
  # require frame iff it expands to a tracked target module.
  defp maybe_put_required(state, segs, scope) do
    with {:ok, mod} <-
           atomic_module(Aliases.expand_alias(segs, LexicalScopeWalker.aliases(scope))),
         true <- MapSet.member?(state.target_keys, mod),
         [current | rest] <- state.require_frames do
      %{state | require_frames: [MapSet.put(current, mod) | rest]}
    else
      _ -> state
    end
  end

  defp current_required(%{require_frames: frames}),
    do: Enum.reduce(frames, MapSet.new(), &MapSet.union/2)

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
