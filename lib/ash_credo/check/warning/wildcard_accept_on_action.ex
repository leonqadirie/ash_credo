defmodule AshCredo.Check.Warning.WildcardAcceptOnAction do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:ash, :security],
    explanations: [
      check: """
      Using `accept :*` on create or update actions accepts all public
      attributes, which is a mass-assignment vulnerability. Explicitly
      list the accepted attributes instead.

          create :create do
            accept [:title, :body]
          end
      """
    ]

  alias AshCredo.Introspection

  @writable_action_types ~w(create update)a

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Introspection.resource_contexts()
    |> Enum.flat_map(fn context ->
      context
      |> Introspection.resource_section(:actions)
      |> check_actions(issue_meta)
    end)
  end

  defp check_actions(nil, _issue_meta), do: []

  defp check_actions(actions_ast, issue_meta) do
    explicit_action_issues(actions_ast, issue_meta) ++
      default_action_issues(actions_ast, issue_meta) ++
      default_accept_issues(actions_ast, issue_meta)
  end

  defp has_wildcard_accept?(entity_ast) do
    entity_ast
    |> Introspection.option_values(:accept)
    |> Enum.any?(&wildcard_accept_value?/1)
  end

  defp explicit_action_issues(actions_ast, issue_meta) do
    actions_ast
    |> Introspection.action_entities(@writable_action_types)
    |> Enum.filter(&has_wildcard_accept?/1)
    |> Enum.map(fn {type, meta, _} = entity ->
      format_issue(issue_meta,
        message:
          "Action `#{Introspection.entity_name(entity) || type}` uses `accept :*`. Explicitly list accepted attributes.",
        trigger: "accept :*",
        line_no: meta[:line]
      )
    end)
  end

  defp default_action_issues(actions_ast, issue_meta) do
    actions_ast
    |> Introspection.entities(:defaults)
    |> Enum.flat_map(&wildcard_default_actions/1)
    |> Enum.map(fn {type, meta} ->
      format_issue(issue_meta,
        message:
          "Default `#{type}` action from `defaults` uses `:*`, which accepts all public attributes. Explicitly list accepted attributes.",
        trigger: "defaults",
        line_no: meta[:line]
      )
    end)
  end

  defp default_accept_issues(actions_ast, issue_meta) do
    actions_ast
    |> Introspection.option_occurrences(:default_accept)
    |> Enum.filter(fn {value, _line_no} -> wildcard_accept_value?(value) end)
    |> Enum.map(fn {_value, line_no} ->
      format_issue(issue_meta,
        message:
          "`default_accept :*` accepts all public attributes on every action. Explicitly list accepted attributes.",
        trigger: "default_accept :*",
        line_no: line_no
      )
    end)
  end

  defp wildcard_default_actions({:defaults, meta, _} = defaults_ast) do
    @writable_action_types
    |> Enum.filter(&Introspection.default_action_has_value?(defaults_ast, &1, :*))
    |> Enum.map(&{&1, meta})
  end

  defp wildcard_accept_value?(value), do: value in [:*, [:*]]
end
