defmodule AshCredo.Check.Warning.SensitiveAttributeExposed do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:ash, :security],
    param_defaults: [
      sensitive_names:
        ~w(password hashed_password password_hash token secret api_key private_key ssn)a
    ],
    explanations: [
      check: """
      Attributes containing sensitive data should be marked with `sensitive?: true`.
      This prevents them from being leaked in logs, error messages, and inspections.

          attribute :password_hash, :string, sensitive?: true
      """,
      params: [
        sensitive_names: "Attribute names considered sensitive."
      ]
    ]

  alias AshCredo.Introspection

  @impl true
  def run(%SourceFile{} = source_file, params) do
    if Introspection.ash_resource?(source_file) do
      sensitive_names = Params.get(params, :sensitive_names, __MODULE__)
      attrs_ast = Introspection.find_dsl_section(source_file, :attributes)
      check_sensitive_attrs(attrs_ast, sensitive_names, source_file, params)
    else
      []
    end
  end

  defp check_sensitive_attrs(nil, _names, _source_file, _params), do: []

  defp check_sensitive_attrs(attrs_ast, sensitive_names, source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    attrs_ast
    |> Introspection.find_entities(:attribute)
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
    name in sensitive_names
  end

  defp sensitive_name?(_, _), do: false
end
