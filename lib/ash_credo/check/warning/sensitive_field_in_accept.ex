defmodule AshCredo.Check.Warning.SensitiveFieldInAccept do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:ash, :security],
    param_defaults: [
      dangerous_fields: ~w(is_admin admin permissions api_key secret_key)a
    ],
    explanations: [
      check: """
      Actions that `accept` privilege-related fields like `:is_admin` or
      `:permissions` can allow users to escalate their own permissions.
      Set these fields via `change` modules instead.

          create :register do
            accept [:name, :email]

            change set_attribute(:role, :user)
          end
      """,
      params: [
        dangerous_fields: "Field names that should not appear in accept lists."
      ]
    ]

  alias AshCredo.Introspection

  @writable_action_types ~w(create update)a

  @impl true
  def run(%SourceFile{} = source_file, params) do
    dangerous = Params.get(params, :dangerous_fields, __MODULE__)
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Introspection.resource_modules()
    |> Enum.flat_map(fn module_ast ->
      module_ast
      |> Introspection.find_dsl_section(:actions)
      |> check_actions(dangerous, issue_meta)
    end)
  end

  defp check_actions(nil, _dangerous, _issue_meta), do: []

  defp check_actions(actions_ast, dangerous, issue_meta) do
    action_issues =
      actions_ast
      |> Introspection.action_entities(@writable_action_types)
      |> Enum.flat_map(&find_dangerous_accepts(&1, dangerous, issue_meta))

    defaults_issues = find_dangerous_defaults(actions_ast, dangerous, issue_meta)
    default_accept_issues = find_dangerous_default_accept(actions_ast, dangerous, issue_meta)

    action_issues ++ defaults_issues ++ default_accept_issues
  end

  defp find_dangerous_accepts(entity_ast, dangerous, issue_meta) do
    entity_ast
    |> Introspection.option_occurrences(:accept)
    |> Enum.flat_map(fn
      {fields, line_no} when is_list(fields) ->
        dangerous_accept_issues(fields, line_no, dangerous, issue_meta, "Action accepts")

      _ ->
        []
    end)
  end

  defp dangerous_accept_issues(fields, line_no, dangerous, issue_meta, prefix) do
    fields
    |> Enum.filter(&(&1 in dangerous))
    |> Enum.map(fn field ->
      format_issue(issue_meta,
        message:
          "#{prefix} `#{field}` which could allow privilege escalation. Use a `change` instead.",
        trigger: "#{field}",
        line_no: line_no
      )
    end)
  end

  defp find_dangerous_defaults(actions_ast, dangerous, issue_meta) do
    actions_ast
    |> Introspection.entities(:defaults)
    |> Enum.flat_map(&dangerous_fields_in_default(&1, dangerous, issue_meta))
  end

  defp dangerous_fields_in_default({:defaults, meta, _} = defaults_ast, dangerous, issue_meta) do
    defaults_ast
    |> Introspection.default_action_entries()
    |> Enum.flat_map(fn
      {type, fields} when type in @writable_action_types and is_list(fields) ->
        fields
        |> Enum.filter(&(&1 in dangerous))
        |> Enum.map(fn field ->
          format_issue(issue_meta,
            message:
              "Default `#{type}` action accepts `#{field}` which could allow privilege escalation. Use a `change` instead.",
            trigger: "#{field}",
            line_no: meta[:line]
          )
        end)

      _ ->
        []
    end)
  end

  defp find_dangerous_default_accept(actions_ast, dangerous, issue_meta) do
    actions_ast
    |> Introspection.option_occurrences(:default_accept)
    |> Enum.flat_map(fn
      {fields, line_no} when is_list(fields) ->
        dangerous_accept_issues(
          fields,
          line_no,
          dangerous,
          issue_meta,
          "`default_accept` includes"
        )

      _ ->
        []
    end)
  end
end
