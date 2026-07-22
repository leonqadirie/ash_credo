defmodule AshCredo.Check.Warning.CompileTimeDefault do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:ash],
    explanations: [
      check: """
      Flags `default` or `update_default` values that come from a direct
      call to a time- or UUID-producing function, like
      `default: DateTime.utc_now()`. DSL options are ordinary expressions
      that Elixir evaluates while the module compiles, so the call runs
      exactly once and the result is baked into the resource as a literal:
      every record gets the timestamp of the last compile, and a default of
      `Ash.UUID.generate()` gives every record the same "unique" value.

      Ash re-evaluates a default per record only when it is a zero-arity
      function or an MFA tuple; it uses any other value verbatim.

          # Bad - frozen at compile time, identical for every record
          attribute :scheduled_at, :utc_datetime, default: DateTime.utc_now()

          # Good - re-evaluated for each record
          attribute :scheduled_at, :utc_datetime, default: &DateTime.utc_now/0

      Action arguments and calculation arguments resolve `default` the same
      way, so the check covers their defaults too. It doesn't flag values
      wrapped in a zero-arity `fn` or a capture; those forms are correct.

      No other tool catches this bug: the code compiles without warnings,
      the frozen value type-checks, and no error is ever raised. In
      development each recompile refreshes the value, so the problem only
      shows up in production.

      `Warning.PinnedTimeInExpression` is the sibling check for the same
      bug class inside Ash expressions (`^DateTime.utc_now()`).
      """
    ]

  alias AshCredo.Introspection
  alias AshCredo.Introspection.Aliases
  alias AshCredo.Introspection.LexicalScopeWalker
  alias AshCredo.Orchestration
  alias Credo.Code.Name

  # Functions whose value is only meaningful when each record gets its own.
  # We match on the module resolved through the lexical environment, like
  # the sibling PinnedTimeInExpression, so we also catch aliased forms
  # (`alias DateTime, as: DT`).
  @frozen_calls [
    {Date, :utc_today},
    {DateTime, :utc_now},
    {NaiveDateTime, :utc_now},
    {Time, :utc_now},
    {Ash.UUID, :generate},
    {Ash.UUIDv7, :generate},
    {Ecto.UUID, :generate}
  ]

  @default_options ~w(default update_default)a

  # Sections where default/update_default options occur: attribute
  # entities, action arguments, and calculation arguments.
  @sections ~w(attributes actions calculations)a

  @impl true
  def run(%SourceFile{} = source_file, params) do
    Orchestration.flat_map_resource_context(source_file, params, fn context, issue_meta ->
      case Enum.flat_map(@sections, &Introspection.resource_sections(context, &1)) do
        [] -> []
        sections -> default_option_issues(context.module_ast, sections, issue_meta)
      end
    end)
  end

  # Collects default/update_default occurrences in both forms: the inline
  # keyword option (`default: value`, a 2-tuple in the AST) and the
  # do-block option call (`default value`). We walk the whole module rather
  # than each section on its own, so directives at the module top are
  # already in the env by the time we reach the sections; `section_depth`
  # gates collection to the sections.
  defp default_option_issues(module_ast, sections, issue_meta) do
    {state, _scope} =
      LexicalScopeWalker.traverse(
        module_ast,
        %{issues: [], section_depth: 0, sections: sections},
        &enter(&1, &2, &3, issue_meta),
        &leave/3
      )

    Enum.reverse(state.issues)
  end

  defp enter(node, scope, state, issue_meta) do
    cond do
      node in state.sections ->
        %{state | section_depth: state.section_depth + 1}

      state.section_depth == 0 ->
        state

      true ->
        collect_option(node, LexicalScopeWalker.env(scope), state, issue_meta)
    end
  end

  defp leave(node, _scope, state) do
    if node in state.sections do
      %{state | section_depth: state.section_depth - 1}
    else
      state
    end
  end

  defp collect_option({option, _meta, [value]}, env, state, issue_meta)
       when option in @default_options do
    %{state | issues: frozen_call_issues(value, option, env, issue_meta) ++ state.issues}
  end

  defp collect_option({option, value}, env, state, issue_meta) when option in @default_options do
    %{state | issues: frozen_call_issues(value, option, env, issue_meta) ++ state.issues}
  end

  defp collect_option(_node, _env, state, _issue_meta), do: state

  # Walks the option value for frozen calls, including inside containers
  # (`default: %{at: DateTime.utc_now()}` is just as frozen). We prune
  # subtrees under `fn` or `&`: there the call is deferred, which is the
  # fix.
  defp frozen_call_issues(value, option, env, issue_meta) do
    {_ast, issues} =
      Macro.prewalk(value, [], fn
        {deferred, _, _}, acc when deferred in [:fn, :&] ->
          {:pruned, acc}

        {{:., _, [{:__aliases__, _, segments}, fun]}, meta, args} = node, acc
        when is_list(args) ->
          if frozen_call?(segments, fun, env) do
            {node, [frozen_issue(segments, fun, option, meta, issue_meta) | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    issues
  end

  defp frozen_call?(segments, fun, env) do
    case Aliases.expand_to_module(segments, env) do
      {:ok, module} -> {module, fun} in @frozen_calls
      :error -> false
    end
  end

  defp frozen_issue(segments, fun, option, meta, issue_meta) do
    called = "#{Name.full(segments)}.#{fun}()"

    format_issue(issue_meta,
      message:
        "`#{called}` in `#{option}` is evaluated once at compile time - every record " <>
          "gets the same frozen value. Use a zero-arity function " <>
          "(`#{option}: &#{Name.full(segments)}.#{fun}/0`) so it runs per record.",
      trigger: called,
      line_no: meta[:line]
    )
  end
end
