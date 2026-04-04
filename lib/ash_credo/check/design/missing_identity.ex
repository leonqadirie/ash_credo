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

  alias AshCredo.Check.Helpers

  @impl true
  def run(%SourceFile{} = source_file, params) do
    if Helpers.ash_resource?(source_file) do
      candidates = Params.get(params, :identity_candidates, __MODULE__)
      attrs_ast = Helpers.find_dsl_section(source_file, :attributes)
      identities_ast = Helpers.find_dsl_section(source_file, :identities)
      check_identities(attrs_ast, identities_ast, candidates, source_file, params)
    else
      []
    end
  end

  defp check_identities(nil, _identities, _candidates, _sf, _params), do: []

  defp check_identities(attrs_ast, identities_ast, candidates, source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    identity_fields = collect_identity_fields(identities_ast)

    attrs_ast
    |> Helpers.find_entities(:attribute)
    |> Enum.filter(fn attr -> Helpers.entity_name(attr) in candidates end)
    |> Enum.reject(fn attr -> Helpers.entity_name(attr) in identity_fields end)
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
    |> Helpers.find_entities(:identity)
    |> Enum.flat_map(fn
      {:identity, _, [_name, fields | _]} when is_list(fields) -> fields
      _ -> []
    end)
    |> MapSet.new()
  end
end
