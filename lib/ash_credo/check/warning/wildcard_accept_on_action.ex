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

  alias AshCredo.Check.Helpers

  @writable_action_types ~w(create update)a

  @impl true
  def run(%SourceFile{} = source_file, params) do
    if Helpers.ash_resource?(source_file) do
      actions_ast = Helpers.find_dsl_section(source_file, :actions)
      check_actions(actions_ast, source_file, params)
    else
      []
    end
  end

  defp check_actions(nil, _source_file, _params), do: []

  defp check_actions(actions_ast, source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    explicit_action_issues(actions_ast, issue_meta) ++
      default_action_issues(actions_ast, issue_meta) ++
      default_accept_issues(actions_ast, issue_meta)
  end

  defp has_wildcard_accept?(entity_ast) do
    in_body =
      case Helpers.find_in_body(entity_ast, :accept) do
        {:accept, _, [:*]} -> true
        {:accept, _, [[:*]]} -> true
        _ -> false
      end

    in_body or Keyword.get(Helpers.entity_opts(entity_ast), :accept) in [:*, [:*]]
  end

  defp explicit_action_issues(actions_ast, issue_meta) do
    @writable_action_types
    |> Enum.flat_map(&Helpers.find_entities(actions_ast, &1))
    |> Enum.filter(&has_wildcard_accept?/1)
    |> Enum.map(fn {type, meta, _} = entity ->
      format_issue(issue_meta,
        message:
          "Action `#{Helpers.entity_name(entity) || type}` uses `accept :*`. Explicitly list accepted attributes.",
        trigger: "accept :*",
        line_no: meta[:line]
      )
    end)
  end

  defp default_action_issues(actions_ast, issue_meta) do
    actions_ast
    |> Helpers.find_entities(:defaults)
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
    case Helpers.find_in_body(actions_ast, :default_accept) do
      {:default_accept, meta, [:*]} ->
        [
          format_issue(issue_meta,
            message:
              "`default_accept :*` accepts all public attributes on every action. Explicitly list accepted attributes.",
            trigger: "default_accept :*",
            line_no: meta[:line]
          )
        ]

      {:default_accept, meta, [[:*]]} ->
        [
          format_issue(issue_meta,
            message:
              "`default_accept :*` accepts all public attributes on every action. Explicitly list accepted attributes.",
            trigger: "default_accept :*",
            line_no: meta[:line]
          )
        ]

      _ ->
        []
    end
  end

  defp wildcard_default_actions({:defaults, meta, _} = defaults_ast) do
    @writable_action_types
    |> Enum.filter(&Helpers.default_action_has_value?(defaults_ast, &1, :*))
    |> Enum.map(&{&1, meta})
  end
end
