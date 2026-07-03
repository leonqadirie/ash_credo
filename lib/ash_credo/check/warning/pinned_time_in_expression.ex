defmodule AshCredo.Check.Warning.PinnedTimeInExpression do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:ash],
    explanations: [
      check: """
      Using `^Date.utc_today()` or `^DateTime.utc_now()` inside an Ash expression
      freezes the value at compile time. The pinned value never changes after
      compilation, leading to subtle bugs that only manifest after time passes.

      Use Ash's built-in expression functions instead:

          # Bad - frozen at compile time
          filter expr(start_date <= ^Date.utc_today())

          # Good - evaluated at runtime
          filter expr(start_date <= today())

          # Bad
          filter expr(inserted_at >= ^DateTime.utc_now())

          # Good
          filter expr(inserted_at >= now())

      Only DSL-position expressions are checked. Inside function bodies
      and anonymous functions the pin is re-evaluated on every call
      (`Ash.Expr.expr/1` splices the pinned code into its call site), so
      it is not frozen and is not flagged.
      """
    ]

  alias AshCredo.Introspection
  alias AshCredo.Introspection.Block
  alias Credo.Code.Name

  # `Time.utc_now` maps to `nil`: Ash has no expression builtin returning
  # the current time of day, so the message advises passing the value in
  # instead of naming a replacement.
  @time_calls %{
    {[:Date], :utc_today} => "today()",
    {[:DateTime], :utc_now} => "now()",
    {[:NaiveDateTime], :utc_now} => "now()",
    {[:Time], :utc_now} => nil
  }

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Introspection.resource_modules()
    |> Enum.flat_map(&module_expr_issues(&1, issue_meta))
  end

  defp find_pinned_time_calls(ast, issue_meta) do
    Credo.Code.prewalk(
      ast,
      fn
        {:^, meta, [{{:., _, [{:__aliases__, _, module}, func]}, _, _}]} = node, acc ->
          case Map.fetch(@time_calls, {module, func}) do
            :error ->
              {node, acc}

            {:ok, replacement} ->
              pinned = "^#{Name.full(module)}.#{func}()"

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
    module_ast
    |> Block.module_body()
    |> Enum.reject(&match?({:defmodule, _, _}, &1))
    |> Enum.flat_map(&expr_issues(&1, issue_meta))
  end

  # Heads whose bodies run after compilation: the pinned call inside them
  # is re-evaluated per invocation, so the freeze bug does not exist there.
  @deferred_heads ~w(def defp defmacro defmacrop fn &)a

  defp expr_issues(ast, issue_meta) do
    Credo.Code.prewalk(
      ast,
      fn
        # An immediately-invoked fn/capture runs while the DSL compiles, so
        # its body is NOT deferred - unwrap it and keep walking the bodies.
        # The call arguments evaluate at the call site too, so walk them
        # as well (`(fn e -> e end).(expr(^DateTime.utc_now()))`).
        {{:., _, [{:fn, _, clauses}]}, _meta, args}, acc when is_list(args) ->
          {{:__block__, [], [clause_bodies(clauses) | args]}, acc}

        {{:., _, [{:&, _, capture_body}]}, _meta, args}, acc when is_list(args) ->
          {{:__block__, [], List.wrap(capture_body) ++ args}, acc}

        {head, _meta, args}, acc when head in @deferred_heads and is_list(args) ->
          {:pruned, acc}

        {:expr, _meta, [body]} = node, acc ->
          {node, find_pinned_time_calls(body, issue_meta) ++ acc}

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
