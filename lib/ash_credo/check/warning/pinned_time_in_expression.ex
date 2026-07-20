defmodule AshCredo.Check.Warning.PinnedTimeInExpression do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:ash],
    explanations: [
      check: """
      Using `^Date.utc_today()` or `^DateTime.utc_now()` inside an Ash
      expression freezes the value at compile time. The pinned value never
      changes after compilation, leading to subtle bugs that only show up
      after time passes.

      Use Ash's built-in expression functions instead:

          # Bad - frozen at compile time
          filter expr(start_date <= ^Date.utc_today())

          # Good - evaluated at runtime
          filter expr(start_date <= today())

          # Bad
          filter expr(inserted_at >= ^DateTime.utc_now())

          # Good
          filter expr(inserted_at >= now())

      Only expressions in DSL position are checked. Inside function
      bodies and anonymous functions the pin is re-evaluated on every call
      (`Ash.Expr.expr/1` splices the pinned code into its call site), so
      the value is not frozen there and is not flagged.
      """
    ]

  alias AshCredo.Introspection
  alias AshCredo.Introspection.Aliases
  alias AshCredo.Introspection.Block
  alias AshCredo.Introspection.LexicalScopeWalker
  alias Credo.Code.Name

  # Keyed on the module resolved through the lexical environment, so
  # aliased forms (`alias DateTime, as: DT`) match too. `Time.utc_now`
  # maps to `nil`: Ash has no expression builtin that returns the current
  # time of day, so the message advises passing the value in instead of
  # naming a replacement.
  @time_calls %{
    {Date, :utc_today} => "today()",
    {DateTime, :utc_now} => "now()",
    {NaiveDateTime, :utc_now} => "now()",
    {Time, :utc_now} => nil
  }

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Introspection.resource_modules()
    |> Enum.flat_map(&module_expr_issues(&1, issue_meta))
  end

  defp find_pinned_time_calls(ast, env, issue_meta) do
    Credo.Code.prewalk(
      ast,
      fn
        {:^, meta, [{{:., _, [{:__aliases__, _, segments}, func]}, _, _}]} = node, acc ->
          case time_call(segments, func, env) do
            :error ->
              {node, acc}

            {:ok, replacement} ->
              pinned = "^#{Name.full(segments)}.#{func}()"

              issue =
                format_issue(issue_meta,
                  message: pinned_message(replacement, pinned),
                  trigger: pinned,
                  line_no: meta[:line]
                )

              {node, [issue | acc]}
          end

        node, acc ->
          {node, acc}
      end,
      []
    )
  end

  # Resolves the pinned call's target module through the env visible at
  # the enclosing `expr`, so an aliased `^DT.utc_now()` matches and an
  # unrelated module's `utc_now` does not.
  defp time_call(segments, func, env) do
    with {:ok, module} <- Aliases.expand_to_module(segments, env) do
      Map.fetch(@time_calls, {module, func})
    end
  end

  defp pinned_message(nil, pinned) do
    "`#{pinned}` is evaluated at compile time and never updates, and no " <>
      "expression builtin returns the current time of day. Pass the value " <>
      "as an action argument, or compare datetimes with `now()`."
  end

  defp pinned_message(replacement, pinned) do
    "Use `#{replacement}` instead of `#{pinned}` in Ash expressions. " <>
      "The pinned call is evaluated at compile time and never updates."
  end

  defp module_expr_issues(module_ast, issue_meta) do
    envs = expr_envs(module_ast)

    module_ast
    |> Block.module_body()
    |> Enum.reject(&match?({:defmodule, _, _}, &1))
    |> Enum.flat_map(&expr_issues(&1, envs, issue_meta))
  end

  # Maps each `expr(...)` node in the module to the `Macro.Env` visible at
  # it, so pinned calls resolve through the directives lexically in scope.
  # Keyed on the node itself: its meta carries line/column, so structural
  # equality identifies the call site.
  defp expr_envs(module_ast) do
    {envs, _scope} =
      LexicalScopeWalker.traverse(
        module_ast,
        %{},
        fn
          {:expr, _, [_body]} = node, scope, acc ->
            Map.put_new(acc, node, LexicalScopeWalker.env(scope))

          _node, _scope, acc ->
            acc
        end,
        fn _node, _scope, acc -> acc end
      )

    envs
  end

  # Heads whose bodies run after compilation: the pinned call inside them
  # is re-evaluated per invocation, so the freeze bug does not exist
  # there.
  @deferred_heads ~w(def defp defmacro defmacrop fn &)a

  defp expr_issues(ast, envs, issue_meta) do
    Credo.Code.prewalk(
      ast,
      fn
        # An immediately-invoked fn/capture runs while the DSL compiles, so
        # its body is NOT deferred: unwrap it and keep walking the bodies.
        # The call arguments evaluate at the call site too, so walk them
        # as well (`(fn e -> e end).(expr(^DateTime.utc_now()))`).
        {{:., _, [{:fn, _, clauses}]}, _meta, args}, acc when is_list(args) ->
          {{:__block__, [], [clause_bodies(clauses) | args]}, acc}

        {{:., _, [{:&, _, capture_body}]}, _meta, args}, acc when is_list(args) ->
          {{:__block__, [], List.wrap(capture_body) ++ args}, acc}

        {head, _meta, args}, acc when head in @deferred_heads and is_list(args) ->
          {:pruned, acc}

        {:expr, _meta, [body]} = node, acc ->
          env = Map.get(envs, node, Aliases.base_env())
          {node, find_pinned_time_calls(body, env, issue_meta) ++ acc}

        node, acc ->
          {node, acc}
      end,
      []
    )
  end

  defp clause_bodies(clauses) when is_list(clauses) do
    {:__block__, [],
     Enum.map(clauses, fn
       {:->, _, [_args, body]} -> body
       other -> other
     end)}
  end

  defp clause_bodies(other), do: other
end
