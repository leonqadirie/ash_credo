defmodule AshCredo.Check.Refactor.DirectiveInFunctionBody do
  use Credo.Check,
    base_priority: :normal,
    category: :refactor,
    tags: [:ash],
    param_defaults: [directive_modules: [Ash.Query, Ash.Expr]],
    explanations: [
      check: """
      Flags `require`/`import`/`alias` directives for configured modules
      when they're declared inside a function body. These directives belong
      at the top of the module so they apply once for the whole file
      instead of being repeated in every function that needs them.

      The default-and-canonical case is `require Ash.Query` and
      `require Ash.Expr`: AI coding assistants frequently drop a fresh
      `require` into every function that uses an `Ash.Query.*` or
      `Ash.Expr.*` macro, instead of requiring the module once at the top
      of the module. The result is files with three or four duplicated
      directives, which is noisy, non-idiomatic, and a recognisable code
      smell.

          # Flagged
          defmodule MyApp.PostQueries do
            def published do
              require Ash.Query
              MyApp.Post |> Ash.Query.filter(Ash.Query.expr(state == :published))
            end

            def draft do
              require Ash.Query
              MyApp.Post |> Ash.Query.filter(Ash.Query.expr(state == :draft))
            end
          end

          # Preferred
          defmodule MyApp.PostQueries do
            require Ash.Query

            def published, do: MyApp.Post |> Ash.Query.filter(Ash.Query.expr(state == :published))
            def draft,     do: MyApp.Post |> Ash.Query.filter(Ash.Query.expr(state == :draft))
          end

      The check is purely syntactic. It walks the source AST tracking the
      depth of `def`/`defp`/`defmacro`/`defmacrop` blocks and emits an issue
      whenever it finds a target directive at depth >= 1.

      Directives generated inside `quote do ... end` blocks are deliberately
      ignored: a macro author writing `quote do require Ash.Query end` injects
      the directive at the call site, not at the macro's own definition site,
      so flagging that case would be a false positive.

      ## Configuration

      `directive_modules` defaults to `[Ash.Query, Ash.Expr]`. The check
      is general - any module you put in the list is checked the same way.
      Add Ash extension modules from your own codebase, or any third-party
      module whose directives you want centralised:

          {AshCredo.Check.Refactor.DirectiveInFunctionBody,
           [directive_modules: [Ash.Query, Ash.Expr, MyApp.CustomMacros]]}

      The check matches the exact module specified. With `[Ash.Query]`
      configured, `require Ash.Query.Aggregation` is NOT flagged - that's
      a different module with its own reasons to be required.

      The default reflects the most common cases in Ash codebases (the
      `require Ash.Query` and `require Ash.Expr` repetition AI assistants
      love). The check itself is general; this plugin just ships
      Ash-flavoured defaults.
      """,
      params: [
        directive_modules:
          "List of modules whose `require`/`import`/`alias` directives must " <>
            "live at module level rather than inside function bodies. Defaults " <>
            "to `[Ash.Query, Ash.Expr]` because those are the most common " <>
            "offenders in Ash codebases. The check itself is general - add " <>
            "any module whose directives your team wants centralised."
      ]
    ]

  @def_kinds ~w(def defp defmacro defmacrop)a
  @directive_kinds ~w(require import alias)a

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    targets = directive_targets(params)

    {_ast, %{issues: issues}} =
      source_file
      |> Credo.SourceFile.ast()
      |> Macro.traverse(
        %{def_depth: 0, quote_depth: 0, def_depth_stack: [], issues: []},
        &enter_node(&1, &2, targets, issue_meta),
        &leave_node/2
      )

    Enum.reverse(issues)
  end

  defp directive_targets(params) do
    params
    |> Params.get(:directive_modules, __MODULE__)
    |> List.wrap()
    |> MapSet.new()
  end

  # 2-arg def_kind = def WITH a body. Bodyless defs (clause heads, default-arg
  # declarations like `def foo(a, b \\ default)`) are 1-arg AST nodes with no
  # `do:` block - skip them so we don't increment depth on a non-existent body.
  defp enter_node({def_kind, _, [_, _]} = node, state, _targets, _issue_meta)
       when def_kind in @def_kinds do
    {node, %{state | def_depth: state.def_depth + 1}}
  end

  # A nested defmodule resets the def context: a directive at the top of an
  # inner module is at module level even if the outer scope is a function body.
  defp enter_node({:defmodule, _, _} = node, state, _targets, _issue_meta) do
    {node, %{state | def_depth: 0, def_depth_stack: [state.def_depth | state.def_depth_stack]}}
  end

  # Suppress emission inside quoted expressions: a macro author who writes
  # `quote do require Ash.Query end` is injecting the directive into the
  # caller's site, not placing it in their own def body. The literal `require`
  # AST exists inside the def but is generated code, not actual placement.
  defp enter_node({:quote, _, _} = node, state, _targets, _issue_meta) do
    {node, %{state | quote_depth: state.quote_depth + 1}}
  end

  defp enter_node(
         {directive, meta, [{:__aliases__, _, segs} | _]} = node,
         state,
         targets,
         issue_meta
       )
       when directive in @directive_kinds and is_list(segs) do
    if state.def_depth > 0 and state.quote_depth == 0 and Enum.all?(segs, &is_atom/1) do
      module = Module.concat(segs)

      if MapSet.member?(targets, module) do
        issue = build_issue(directive, module, meta, issue_meta)
        {node, %{state | issues: [issue | state.issues]}}
      else
        {node, state}
      end
    else
      {node, state}
    end
  end

  defp enter_node(node, state, _targets, _issue_meta), do: {node, state}

  defp leave_node({:defmodule, _, _} = node, %{def_depth_stack: [saved | rest]} = state) do
    {node, %{state | def_depth: saved, def_depth_stack: rest}}
  end

  defp leave_node({def_kind, _, [_, _]} = node, state) when def_kind in @def_kinds do
    {node, %{state | def_depth: max(state.def_depth - 1, 0)}}
  end

  defp leave_node({:quote, _, _} = node, state) do
    {node, %{state | quote_depth: max(state.quote_depth - 1, 0)}}
  end

  defp leave_node(node, state), do: {node, state}

  defp build_issue(directive, module, meta, issue_meta) do
    target = inspect(module)

    format_issue(issue_meta,
      message:
        "`#{directive} #{target}` is declared inside a function body. " <>
          "Move it to the top of the module so it applies once for the whole file.",
      trigger: target,
      line_no: meta[:line]
    )
  end
end
