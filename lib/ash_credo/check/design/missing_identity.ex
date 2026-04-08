defmodule AshCredo.Check.Design.MissingIdentity do
  use Credo.Check,
    base_priority: :normal,
    category: :design,
    tags: [:ash],
    param_defaults: [
      identity_candidates: ~w(email username slug handle phone)a
    ],
    explanations: [
      check: """
      Attributes like `email`, `username`, or `slug` are almost always
      intended to be unique. Add a corresponding identity:

          identities do
            identity :unique_email, [:email]
          end
      """,
      params: [
        identity_candidates: "Attribute names that should have a uniqueness identity."
      ]
    ]

  alias AshCredo.Introspection

  @impl true
  def run(%SourceFile{} = source_file, params) do
    candidates = Params.get(params, :identity_candidates, __MODULE__)
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Introspection.resource_contexts()
    |> Enum.flat_map(fn context ->
      attrs_ast = Introspection.resource_section(context, :attributes)
      identities_ast = Introspection.resource_section(context, :identities)
      check_identities(attrs_ast, identities_ast, candidates, issue_meta)
    end)
  end

  defp check_identities(nil, _identities, _candidates, _issue_meta), do: []

  defp check_identities(attrs_ast, identities_ast, candidates, issue_meta) do
    identity_fields = collect_identity_fields(identities_ast)

    attrs_ast
    |> Introspection.entities(:attribute)
    |> Enum.filter(fn attr -> Introspection.entity_name(attr) in candidates end)
    |> Enum.reject(fn attr -> Introspection.entity_name(attr) in identity_fields end)
    |> Enum.map(fn {_, meta, [name | _]} ->
      format_issue(issue_meta,
        message: "Attribute `#{name}` likely needs a uniqueness identity.",
        trigger: "#{name}",
        line_no: meta[:line]
      )
    end)
  end

  defp collect_identity_fields(nil), do: MapSet.new()

  defp collect_identity_fields(identities_ast) do
    identities_ast
    |> Introspection.entities(:identity)
    |> Enum.flat_map(fn
      {:identity, _, [_name, fields | _]} when is_list(fields) -> fields
      _ -> []
    end)
    |> MapSet.new()
  end
end
