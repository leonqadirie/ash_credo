defmodule AshCredo.Check.Warning.SensitiveFieldInAccept do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:ash, :security],
    param_defaults: [
      dangerous_fields: ~w(is_admin admin permissions api_key secret_key)a,
      excluded_paths: [~r"/test/", "test"]
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

      Create, update, and soft destroy actions are checked. Hard destroy
      actions are not: Ash resets their `accept` to `[]` at compile time,
      so an accept list there takes no input.

      Test directories are excluded by default, since test factories and seeds
      often accept these fields on purpose. Override `excluded_paths` to scope
      the check differently.
      """,
      params: [
        dangerous_fields:
          "Field names that should not appear in accept lists. Atom entries " <>
            "match exactly; `Regex` entries (e.g. `~r/_token$/`) match against " <>
            "the field name.",
        excluded_paths:
          "List of paths or regexes to exclude from this check. " <>
            "Defaults to test directories, since accepting these fields is " <>
            "often intentional in test setup."
      ]
    ]

  alias AshCredo.{Introspection, PathFilter}
  alias AshCredo.Introspection.ResourceContext

  # For the `defaults` list only: `defaults [destroy: :*]` raises a DslError
  # in Ash, so keyword defaults entries can never carry a destroy accept.
  @default_writable_action_types ~w(create update)a

  @impl true
  def run(%SourceFile{} = source_file, params) do
    excluded_paths = Params.get(params, :excluded_paths, __MODULE__)

    if PathFilter.excluded?(source_file.filename, excluded_paths) do
      []
    else
      find_issues(source_file, params)
    end
  end

  defp find_issues(%SourceFile{} = source_file, params) do
    dangerous = Params.get(params, :dangerous_fields, __MODULE__)
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Introspection.resource_contexts()
    |> Enum.flat_map(fn %ResourceContext{} = context ->
      context
      |> Introspection.resource_section(:actions)
      |> check_actions(dangerous, issue_meta)
    end)
  end

  defp check_actions(nil, _dangerous, _issue_meta), do: []

  defp check_actions(actions_ast, dangerous, issue_meta) do
    action_issues =
      actions_ast
      |> Introspection.accepting_action_entities()
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
    |> Enum.filter(&dangerous_field?(&1, dangerous))
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
      {type, default_fields}
      when type in @default_writable_action_types and is_list(default_fields) ->
        default_fields
        |> Enum.filter(&dangerous_field?(&1, dangerous))
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

  defp dangerous_field?(field, dangerous) do
    Enum.any?(dangerous, &field_matches?(field, &1))
  end

  defp field_matches?(field, %Regex{} = regex) when is_atom(field),
    do: Regex.match?(regex, Atom.to_string(field))

  defp field_matches?(_field, %Regex{}), do: false
  defp field_matches?(field, name), do: field == name
end
