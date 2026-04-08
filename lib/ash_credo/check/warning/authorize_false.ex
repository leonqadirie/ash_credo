defmodule AshCredo.Check.Warning.AuthorizeFalse do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:ash, :security],
    param_defaults: [include_non_ash_calls: true],
    explanations: [
      check: """
      Using `authorize?: false` bypasses Ash authorization entirely, making it
      easy to accidentally skip policy checks. Instead, use system actors with
      bypass policies so that authorization is always enforced and auditable.

          # Bad — skips all authorization
          Ash.read!(query, authorize?: false)

          # Good — uses a named system actor
          Ash.read!(query, actor: %{system: :my_context})

          # In resource policies:
          bypass expr(not is_nil(^actor(:system))) do
            authorize_if always()
          end

      For code inside action changes/validations that needs to read related data,
      use `scope: context` to inherit the caller's authorization context:

          Ash.get!(Resource, id, scope: context)

      **Note:** By default this check flags `authorize?: false` anywhere it appears as a
      literal — Ash API calls, action DSL definitions, variable assignments, and
      wrapper functions. Set `include_non_ash_calls: false` to restrict detection
      to Ash API calls and action DSL definitions only.

      In either mode the check is purely syntactic: it cannot follow values through
      variables, config lookups, or function return values.
      """,
      params: [
        include_non_ash_calls:
          "When `true` (default), flags `authorize?: false` anywhere in source. " <>
            "When `false`, only checks Ash API calls and action DSL definitions."
      ]
    ]

  alias AshCredo.Introspection

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    lines =
      if Params.get(params, :include_non_ash_calls, __MODULE__) do
        all_authorize_false_lines(source_file)
      else
        ash_authorize_false_lines(source_file)
      end

    Enum.map(lines, fn line ->
      format_issue(issue_meta,
        message:
          "`authorize?: false` bypasses authorization. Use system actors with bypass policies instead.",
        trigger: "authorize?: false",
        line_no: line
      )
    end)
  end

  defp ash_authorize_false_lines(source_file) do
    call_lines =
      source_file
      |> Introspection.ash_api_calls()
      |> Enum.flat_map(fn {_call, meta, args} ->
        if has_authorize_false?(args), do: [meta[:line]], else: []
      end)

    action_lines =
      source_file
      |> Introspection.resource_contexts()
      |> Enum.flat_map(fn context ->
        context
        |> Introspection.resource_section(:actions)
        |> action_authorize_false_lines()
      end)

    Enum.sort(Enum.uniq(call_lines ++ action_lines))
  end

  defp action_authorize_false_lines(nil), do: []

  defp action_authorize_false_lines(actions_ast) do
    actions_ast
    |> Introspection.action_entities()
    |> Enum.flat_map(fn action ->
      action
      |> Introspection.option_occurrences(:authorize?)
      |> Enum.flat_map(fn
        {false, line} -> [line]
        _ -> []
      end)
    end)
  end

  defp all_authorize_false_lines(source_file) do
    literal_lines =
      Credo.Code.prewalk(
        source_file,
        fn
          {_name, meta, args} = ast, acc when is_list(args) and is_list(meta) ->
            if has_authorize_false?(args) do
              {ast, [meta[:line] | acc]}
            else
              {ast, acc}
            end

          ast, acc ->
            {ast, acc}
        end,
        []
      )

    Enum.sort(Enum.uniq(ash_authorize_false_lines(source_file) ++ literal_lines))
  end

  defp has_authorize_false?(args) do
    Enum.any?(args, fn
      {:authorize?, false} -> true
      kwl when is_list(kwl) -> Keyword.get(kwl, :authorize?) == false
      _ -> false
    end)
  end
end
