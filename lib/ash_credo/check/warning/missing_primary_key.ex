defmodule AshCredo.Check.Warning.MissingPrimaryKey do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:ash],
    explanations: [
      check: """
      Ash resources backed by a data layer need a primary key.
      Missing one causes runtime errors on reads and relationships.

      Add one of these inside your `attributes` block:

          uuid_primary_key :id
          uuid_v7_primary_key :id
          integer_primary_key :id
          attribute :id, :uuid, primary_key?: true, allow_nil?: false
      """
    ]

  alias AshCredo.Introspection

  @primary_key_entities ~w(uuid_primary_key uuid_v7_primary_key integer_primary_key)a

  @impl true
  def run(%SourceFile{} = source_file, params) do
    if Introspection.ash_resource?(source_file) and Introspection.has_data_layer?(source_file) do
      attrs_ast = Introspection.find_dsl_section(source_file, :attributes)
      rels_ast = Introspection.find_dsl_section(source_file, :relationships)
      check_for_primary_key(attrs_ast, rels_ast, source_file, params)
    else
      []
    end
  end

  defp check_for_primary_key(attrs_ast, rels_ast, source_file, params) do
    if has_pk_entity?(attrs_ast) or has_pk_attribute?(attrs_ast) or has_pk_relationship?(rels_ast) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)

      [
        format_issue(issue_meta,
          message: "Resource is missing a primary key.",
          trigger: "attributes",
          line_no:
            Introspection.section_line(attrs_ast) ||
              Introspection.find_use_line(source_file, [:Ash, :Resource]) || 1
        )
      ]
    end
  end

  defp has_pk_entity?(nil), do: false

  defp has_pk_entity?(attrs_ast) do
    Enum.any?(@primary_key_entities, &Introspection.has_entity?(attrs_ast, &1))
  end

  defp has_pk_attribute?(nil), do: false

  defp has_pk_attribute?(attrs_ast) do
    attrs_ast
    |> Introspection.find_entities(:attribute)
    |> Enum.any?(&Introspection.entity_has_opt?(&1, :primary_key?, true))
  end

  defp has_pk_relationship?(nil), do: false

  defp has_pk_relationship?(rels_ast) do
    rels_ast
    |> Introspection.find_entities(:belongs_to)
    |> Enum.any?(&Introspection.entity_has_opt?(&1, :primary_key?, true))
  end
end
