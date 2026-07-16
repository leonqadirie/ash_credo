defmodule AshCredo.Check.Warning.WildcardAcceptOnAction do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:ash, :security],
    param_defaults: [
      excluded_paths: [~r"/test/", "test"]
    ],
    explanations: [
      check: """
      Using `accept :*` on create, update, or soft destroy actions accepts
      all public attributes, which is a mass-assignment vulnerability.
      Explicitly list the accepted attributes instead.

          create :create do
            accept [:title, :body]
          end

      Hard destroy actions are not checked: Ash resets their `accept` to
      `[]` at compile time, so an accept list there takes no input. Soft
      destroys are updates under the hood and honor `accept` like any
      other writable action.

      Test directories are excluded by default, since test factories and seeds
      often use `accept :*` on purpose. Override `excluded_paths` to scope the
      check differently.
      """,
      params: [
        excluded_paths:
          "List of paths or regexes to exclude from this check. " <>
            "Defaults to test directories, since `accept :*` is often " <>
            "intentional in test setup."
      ]
    ]

  alias AshCredo.{Introspection, PathFilter}
  alias AshCredo.Orchestration

  # For the `defaults` list only: `defaults [destroy: :*]` raises a DslError
  # in Ash, so keyword defaults entries can never carry a destroy accept.
  @default_writable_action_types ~w(create update)a

  @impl true
  def run(%SourceFile{} = source_file, params) do
    excluded_paths = Params.get(params, :excluded_paths, __MODULE__)

    if PathFilter.excluded?(source_file.filename, excluded_paths) do
      []
    else
      Orchestration.flat_map_resource_section(source_file, params, :actions, &check_actions/2)
    end
  end

  defp check_actions(actions_ast, issue_meta) do
    explicit_action_issues(actions_ast, issue_meta) ++
      default_action_issues(actions_ast, issue_meta) ++
      default_accept_issues(actions_ast, issue_meta)
  end

  defp explicit_action_issues(actions_ast, issue_meta) do
    source_file = IssueMeta.source_file(issue_meta)

    actions_ast
    |> Introspection.accepting_action_entities()
    |> Enum.flat_map(fn {type, _meta, _} = entity ->
      entity
      |> Introspection.option_occurrences(:accept)
      |> Enum.filter(fn {value, _line_no} -> wildcard_accept_value?(value) end)
      |> Enum.map(fn {_value, line_no} ->
        format_issue(issue_meta,
          message:
            "Action `#{Introspection.entity_name(entity) || type}` uses `accept :*`. Explicitly list accepted attributes.",
          trigger: "accept :*",
          line_no: line_no,
          column: SourceFile.column(source_file, line_no, "accept")
        )
      end)
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

  # `default_accept` only reaches actions that can inherit it; on a
  # resource with none (e.g. only reads and hard destroys) the option is
  # dead configuration, not a mass-assignment surface.
  defp default_accept_issues(actions_ast, issue_meta) do
    if Introspection.default_accept_inheritors?(actions_ast) do
      wildcard_default_accept_issues(actions_ast, issue_meta)
    else
      []
    end
  end

  defp wildcard_default_accept_issues(actions_ast, issue_meta) do
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
    @default_writable_action_types
    |> Enum.filter(&Introspection.default_action_has_value?(defaults_ast, &1, :*))
    |> Enum.map(&{&1, meta})
  end

  defp wildcard_accept_value?(value), do: value in [:*, [:*]]
end
