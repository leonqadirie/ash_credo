defmodule AshCredo.Check.Warning.AuthorizeFalse do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:ash, :security],
    param_defaults: [
      include_non_ash_calls: true,
      excluded_paths: AshCredo.PathFilter.default_excluded_paths()
    ],
    explanations: [
      check: """
      Passing `authorize?: false` bypasses Ash authorization entirely, which
      makes it easy to skip policy checks by accident. Use system actors with
      bypass policies instead, so authorization stays enforced and auditable.

          # Bad - skips all authorization
          Ash.read!(query, authorize?: false)

          # Good - uses a named system actor
          Ash.read!(query, actor: %{system: :my_context})

          # In resource policies:
          bypass expr(not is_nil(^actor(:system))) do
            authorize_if always()
          end

      Code inside action changes or validations sometimes needs to read
      related data. There, use `scope: context` to inherit the caller's
      authorization context:

          Ash.get!(Resource, id, scope: context)

      By default, the check flags `authorize?: false` anywhere it appears as
      a literal: Ash API calls, action DSL definitions, variable assignments,
      and wrapper functions. Set `include_non_ash_calls: false` to restrict
      detection to Ash API calls and action DSL definitions.

      The check excludes test directories by default, since bypassing
      authorization in test setup and factories is usually intentional.
      Override `excluded_paths` to scope the check differently.

      In either mode, the check is purely syntactic: it cannot follow values
      through variables, config lookups, or function return values.
      """,
      params: [
        include_non_ash_calls:
          "When `true` (the default), flags `authorize?: false` anywhere it appears " <>
            "in the source. When `false`, only checks Ash API calls and " <>
            "action DSL definitions.",
        excluded_paths:
          "Paths or regexes to exclude from this check. Defaults to the test " <>
            "directories, since `authorize?: false` is intentional in test setup."
      ]
    ]

  alias AshCredo.{Introspection, PathFilter}
  alias AshCredo.Introspection.{AshCallScanner, ResourceContext}

  @impl true
  def run(%SourceFile{} = source_file, params) do
    excluded_paths = Params.get(params, :excluded_paths, __MODULE__)

    if PathFilter.excluded?(source_file.filename, excluded_paths) do
      []
    else
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
  end

  defp ash_authorize_false_lines(source_file) do
    call_lines =
      for {_call, meta, args} <- AshCallScanner.calls(source_file),
          has_authorize_false?(args),
          do: meta[:line]

    action_lines =
      source_file
      |> Introspection.resource_contexts()
      |> Enum.flat_map(fn %ResourceContext{} = context ->
        context
        |> Introspection.resource_sections(:actions)
        |> action_authorize_false_lines()
      end)

    Enum.sort(Enum.uniq(call_lines ++ action_lines))
  end

  defp action_authorize_false_lines(actions_ast) do
    for action <- Introspection.action_entities(actions_ast),
        {false, line} <- Introspection.option_occurrences(action, :authorize?),
        do: line
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
      # A bare `authorize?` variable has a 3-tuple AST ({:authorize?, meta, nil})
      # that Keyword.get's :lists.keyfind would match, so only accept literal
      # 2-tuples here.
      kwl when is_list(kwl) -> Enum.any?(kwl, &match?({:authorize?, false}, &1))
      _ -> false
    end)
  end
end
