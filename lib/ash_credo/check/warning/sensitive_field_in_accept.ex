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
    if Introspection.ash_resource?(source_file) do
      dangerous = Params.get(params, :dangerous_fields, __MODULE__)
      actions_ast = Introspection.find_dsl_section(source_file, :actions)
      check_actions(actions_ast, dangerous, source_file, params)
    else
      []
    end
  end

  defp check_actions(nil, _dangerous, _source_file, _params), do: []

  defp check_actions(actions_ast, dangerous, source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    action_issues =
      @writable_action_types
      |> Enum.flat_map(&Introspection.find_entities(actions_ast, &1))
      |> Enum.flat_map(&find_dangerous_accepts(&1, dangerous, issue_meta))

    defaults_issues = find_dangerous_defaults(actions_ast, dangerous, issue_meta)
    default_accept_issues = find_dangerous_default_accept(actions_ast, dangerous, issue_meta)

    action_issues ++ defaults_issues ++ default_accept_issues
  end

  defp find_dangerous_accepts(entity_ast, dangerous, issue_meta) do
    body_fields =
      case Introspection.find_in_body(entity_ast, :accept) do
        {:accept, meta, [fields]} when is_list(fields) -> {fields, meta}
        _ -> nil
      end

    inline_fields =
      case Keyword.get(Introspection.entity_opts(entity_ast), :accept) do
        fields when is_list(fields) ->
          {_, meta, _} = entity_ast
          {fields, meta}

        _ ->
          nil
      end

    [body_fields, inline_fields]
    |> Enum.reject(&is_nil/1)
    |> Enum.flat_map(fn {fields, meta} ->
      fields
      |> Enum.filter(&(&1 in dangerous))
      |> Enum.map(fn field ->
        format_issue(issue_meta,
          message:
            "Action accepts `#{field}` which could allow privilege escalation. Use a `change` instead.",
          trigger: "#{field}",
          line_no: meta[:line]
        )
      end)
    end)
  end

  defp find_dangerous_defaults(actions_ast, dangerous, issue_meta) do
    actions_ast
    |> Introspection.find_entities(:defaults)
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
    case Introspection.find_in_body(actions_ast, :default_accept) do
      {:default_accept, meta, [fields]} when is_list(fields) ->
        fields
        |> Enum.filter(&(&1 in dangerous))
        |> Enum.map(fn field ->
          format_issue(issue_meta,
            message:
              "`default_accept` includes `#{field}` which could allow privilege escalation. Use a `change` instead.",
            trigger: "#{field}",
            line_no: meta[:line]
          )
        end)

      _ ->
        []
    end
  end
end
