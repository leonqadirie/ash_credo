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

  alias AshCredo.Introspection.{Aliases, LexicalAliases}
  alias AshCredo.Introspection.Compiled, as: CompiledIntrospection

  @directive_kinds ~w(require import)a
  @scope_keys ~w(do else after rescue catch)a
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
  # the enclosing lexical scope.
  defp collect_module_bodies(ast, target_keys) do
    {_, %{bodies: bodies}} =
      Macro.traverse(
        ast,
        %{
          alias_frames: [[]],
          require_frames: [MapSet.new()],
          quote_depth: 0,
          target_keys: target_keys,
          bodies: []
        },
        &enter_for_bodies/2,
        &leave_for_bodies/2
      )

    Enum.reverse(bodies)
  end

  defp enter_for_bodies({scope_key, _body} = node, state) when scope_key in @scope_keys do
    {node, state |> push_alias_frame() |> push_require_frame()}
  end

  defp enter_for_bodies({:->, _, [_args, _body]} = node, state) do
    {node, state |> push_alias_frame() |> push_require_frame()}
  end

  defp enter_for_bodies({construct, _, _} = node, state)
       when construct in @construct_scope_nodes do
    {node, state |> push_alias_frame() |> push_require_frame()}
  end

  defp enter_for_bodies({:alias, _, _} = node, %{quote_depth: 0} = state) do
    {node, put_aliases(state, Aliases.alias_entries(node))}
  end

  defp enter_for_bodies(
         {directive, _, [{:__aliases__, _, segs} | _]} = node,
         %{quote_depth: 0} = state
       )
       when directive in @directive_kinds do
    {node, maybe_put_required(state, segs)}
  end

  # Skip into `quote do ... end` so a `defmodule` inside generated code is
  # NOT recorded as a real module - it gets compiled at the macro caller's
  # site, not here. Aliases and requires inside quote are likewise not
  # recorded.
  defp enter_for_bodies({:quote, _, _} = node, state) do
    {node, %{state | quote_depth: state.quote_depth + 1}}
  end

  defp enter_for_bodies({:defmodule, _, [_alias, [do: body]]} = node, %{quote_depth: 0} = state) do
    captured = {body, current_aliases(state), current_required(state)}
    {node, %{state | bodies: [captured | state.bodies]}}
  end

  defp enter_for_bodies(node, state), do: {node, state}

  defp leave_for_bodies({scope_key, _body} = node, state) when scope_key in @scope_keys do
    {node, state |> pop_alias_frame() |> pop_require_frame()}
  end

  defp leave_for_bodies({:->, _, [_args, _body]} = node, state) do
    {node, state |> pop_alias_frame() |> pop_require_frame()}
  end

  defp leave_for_bodies({construct, _, _} = node, state)
       when construct in @construct_scope_nodes do
    {node, state |> pop_alias_frame() |> pop_require_frame()}
  end

  defp leave_for_bodies({:quote, _, _} = node, state) do
    {node, %{state | quote_depth: max(state.quote_depth - 1, 0)}}
  end

  defp leave_for_bodies(node, state), do: {node, state}

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
  # we seed the module-body frame. `inherited_aliases` and `inherited_required`
  # pre-populate the base frames with aliases and requires visible from any
  # enclosing `defmodule`, so a nested module's calls expand and resolve the
  # same way Elixir does.
  defp collect_call_sites(body, inherited_aliases, inherited_required, resolved, target_keys) do
    {_ast, %{sites: sites}} =
      Macro.traverse(
        body,
        %{
          defmodule_depth: 0,
          quote_depth: 0,
          alias_frames: [inherited_aliases],
          require_frames: [inherited_required],
          target_keys: target_keys,
          sites: []
        },
        &enter_for_calls(&1, &2, resolved),
        &leave_for_calls/2
      )

    Enum.reverse(sites)
  end

  # Push a new alias and require frame on every `do/else/after/rescue/catch`
  # block and on every `->` arrow clause. This mirrors the lexical scoping
  # rules Elixir uses for `alias`/`require`/`import` and matches
  # `AshCallScanner`'s behaviour.
  defp enter_for_calls({scope_key, _body} = node, state, _resolved)
       when scope_key in @scope_keys do
    {node, state |> push_alias_frame() |> push_require_frame()}
  end

  defp enter_for_calls({:->, _, [_args, _body]} = node, state, _resolved) do
    {node, state |> push_alias_frame() |> push_require_frame()}
  end

  defp enter_for_calls({construct, _, _} = node, state, _resolved)
       when construct in @construct_scope_nodes do
    {node, state |> push_alias_frame() |> push_require_frame()}
  end

  defp enter_for_calls({:alias, _, _} = node, state, _resolved) do
    {node, put_aliases(state, Aliases.alias_entries(node))}
  end

  defp enter_for_calls({directive, _, [{:__aliases__, _, segs} | _]} = node, state, _resolved)
       when directive in @directive_kinds do
    {node, maybe_put_required(state, segs)}
  end

  # Skip into a nested defmodule - its contents belong to the inner module,
  # and will be processed on its own pass via `collect_module_bodies/2`.
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
  # Expand `segs` against the visible alias frames so `alias Ash.Query, as: Q;
  # Q.filter(...)` is matched the same as a literal `Ash.Query.filter(...)`.
  defp enter_for_calls(
         {{:., _, [{:__aliases__, _, segs}, fun]}, meta, args} = node,
         state,
         resolved
       )
       when is_atom(fun) and is_list(args) do
    with true <- state.defmodule_depth == 0 and state.quote_depth == 0,
         {:ok, mod} <- atomic_module(Aliases.expand_alias(segs, current_aliases(state))) do
      maybe_record_call(node, state, resolved, mod, fun, args, meta)
    else
      _ -> {node, state}
    end
  end

  defp enter_for_calls(node, state, _resolved), do: {node, state}

  defp maybe_record_call(node, state, resolved, mod, fun, args, meta) do
    with {:ok, macros} <- Map.fetch(resolved, mod),
         true <- MapSet.member?(macros, fun),
         false <- MapSet.member?(current_required(state), mod) do
      site = %{module: mod, fun: fun, arity: length(args), line: meta[:line]}
      {node, %{state | sites: [site | state.sites]}}
    else
      _ -> {node, state}
    end
  end

  defp leave_for_calls({scope_key, _body} = node, state) when scope_key in @scope_keys do
    {node, state |> pop_alias_frame() |> pop_require_frame()}
  end

  defp leave_for_calls({:->, _, [_args, _body]} = node, state) do
    {node, state |> pop_alias_frame() |> pop_require_frame()}
  end

  defp leave_for_calls({construct, _, _} = node, state)
       when construct in @construct_scope_nodes do
    {node, state |> pop_alias_frame() |> pop_require_frame()}
  end

  defp leave_for_calls({:defmodule, _, _} = node, state) do
    {node, %{state | defmodule_depth: max(state.defmodule_depth - 1, 0)}}
  end

  defp leave_for_calls({:quote, _, _} = node, state) do
    {node, %{state | quote_depth: max(state.quote_depth - 1, 0)}}
  end

  defp leave_for_calls(node, state), do: {node, state}

  defp push_alias_frame(state), do: update_in(state.alias_frames, &LexicalAliases.push_frame/1)

  defp pop_alias_frame(state), do: update_in(state.alias_frames, &LexicalAliases.pop_frame/1)

  defp put_aliases(state, new_aliases),
    do: update_in(state.alias_frames, &LexicalAliases.put_aliases(&1, new_aliases))

  defp current_aliases(%{alias_frames: frames}), do: LexicalAliases.current_aliases(frames)

  defp push_require_frame(state), do: update_in(state.require_frames, &[MapSet.new() | &1])

  defp pop_require_frame(%{require_frames: [_ | rest]} = state),
    do: %{state | require_frames: rest}

  defp pop_require_frame(state), do: state

  # Resolve `segs` against the visible alias frames, then add to the current
  # require frame iff it expands to a tracked target module.
  defp maybe_put_required(state, segs) do
    with {:ok, mod} <- atomic_module(Aliases.expand_alias(segs, current_aliases(state))),
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
