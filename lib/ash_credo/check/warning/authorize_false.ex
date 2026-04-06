defmodule AshCredo.Check.Warning.AuthorizeFalse do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:ash, :security],
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

      **Note:** This check detects `authorize?: false` anywhere it appears as a literal in
      the source — in Ash API calls, action DSL definitions, variable assignments,
      keyword list construction, and wrapper functions. It cannot follow values
      through non-literal expressions (e.g. config lookups or function return values).
      """
    ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> find_authorize_false_lines()
    |> Enum.map(fn line ->
      format_issue(issue_meta,
        message:
          "`authorize?: false` bypasses authorization. Use system actors with bypass policies instead.",
        trigger: "authorize?: false",
        line_no: line
      )
    end)
  end

  defp find_authorize_false_lines(source_file) do
    Credo.Code.prewalk(
      source_file,
      fn
        {:authorize?, meta, [false]} = ast, acc ->
          {ast, [meta[:line] | acc]}

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
    |> Enum.uniq()
  end

  defp has_authorize_false?(args) do
    Enum.any?(args, fn
      {:authorize?, false} -> true
      kwl when is_list(kwl) -> Keyword.get(kwl, :authorize?) == false
      _ -> false
    end)
  end
end
