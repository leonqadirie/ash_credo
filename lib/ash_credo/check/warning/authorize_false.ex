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

      Note: this check only detects `authorize?: false` passed directly in a
      function call. It cannot follow values through variables or configuration,
      so a clean result does not guarantee the option is absent from your codebase.
      Consider supplementing with `grep -r "authorize?: false"` for a full audit.
      """
    ]

  alias AshCredo.Introspection

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    Credo.Code.prewalk(
      source_file,
      fn
        {_call, meta, args} = ast, acc when is_list(args) ->
          if Introspection.ash_api_call?(ast) and has_authorize_false?(args) do
            issue =
              format_issue(issue_meta,
                message:
                  "`authorize?: false` bypasses authorization. Use `actor: %{system: :context_name}` with a bypass policy instead.",
                trigger: "authorize?: false",
                line_no: meta[:line]
              )

            {ast, [issue | acc]}
          else
            {ast, acc}
          end

        ast, acc ->
          {ast, acc}
      end,
      []
    )
  end

  defp has_authorize_false?(args) do
    Enum.any?(args, fn
      {:authorize?, false} -> true
      args when is_list(args) -> Keyword.get(args, :authorize?) == false
      _ -> false
    end)
  end
end
