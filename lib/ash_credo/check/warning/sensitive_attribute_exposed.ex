defmodule AshCredo.Check.Warning.SensitiveAttributeExposed do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:ash, :security],
    param_defaults: [
      sensitive_names:
        ~w(password hashed_password password_hash password_digest token access_token secret client_secret totp_secret api_key private_key ssn)a,
      excluded_paths: AshCredo.PathFilter.default_excluded_paths()
    ],
    explanations: [
      check: """
      Attributes containing sensitive data should be marked with `sensitive?: true`.
      This prevents them from leaking into logs, error messages, and inspections.

          attribute :password_hash, :string, sensitive?: true

      The `sensitive_names` param accepts atoms (exact name match) and
      regexes (matched against the attribute name), for example
      `[:ssn, ~r/_token$/]`.

      The check excludes test directories by default, since throwaway
      resources in test support often use sensitive field names without
      holding real data. Override `excluded_paths` to scope the check
      differently.

      ## Limitations

      The check scans the source AST, so it only sees attributes written
      literally in the `attributes` block. It cannot see attributes
      contributed by Spark transformers or extensions, such as
      `AshAuthentication`'s `:hashed_password`, and will not flag them
      even when they are unmarked.

      The check also only inspects the `attribute` entity: `belongs_to`
      foreign keys cannot be marked `sensitive?` directly (declare the
      column as an explicit `attribute` if you need that), and timestamps
      are not sensitive data, so neither is flagged.
      """,
      params: [
        sensitive_names:
          "Attribute names considered sensitive. Atom entries match exactly; " <>
            "`Regex` entries (for example `~r/_token$/`) match against " <>
            "the attribute name.",
        excluded_paths:
          "List of paths or regexes to exclude from this check. " <>
            "Defaults to test directories, since fake sensitive attributes " <>
            "are common in test resources."
      ]
    ]

  alias AshCredo.{Introspection, NameFilter, PathFilter}

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
    sensitive_names = Params.get(params, :sensitive_names, __MODULE__)
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Introspection.resource_modules()
    |> Enum.flat_map(fn module_ast ->
      module_ast
      |> Introspection.find_dsl_sections(:attributes)
      |> check_sensitive_attrs(sensitive_names, issue_meta)
    end)
  end

  defp check_sensitive_attrs(attrs_ast, sensitive_names, issue_meta) do
    attrs_ast
    |> Introspection.entities(:attribute)
    |> Enum.filter(&sensitive_name?(&1, sensitive_names))
    |> Enum.reject(&Introspection.entity_has_opt?(&1, :sensitive?, true))
    |> Enum.map(fn {_name, meta, [attr_name | _]} ->
      format_issue(issue_meta,
        message: "Attribute `#{attr_name}` looks sensitive but is not marked `sensitive?: true`.",
        trigger: "#{attr_name}",
        line_no: meta[:line]
      )
    end)
  end

  defp sensitive_name?({:attribute, _meta, [name | _]}, sensitive_names) when is_atom(name) do
    NameFilter.matches_any?(name, sensitive_names)
  end

  defp sensitive_name?(_, _), do: false
end
