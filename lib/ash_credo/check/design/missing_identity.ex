defmodule AshCredo.Check.Design.MissingIdentity do
  use AshCredo.CompiledCheck,
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

      An attribute that is the sole primary key is already unique and is
      not flagged - for uniqueness enforcement an identity adds nothing
      there. Define one anyway if you want to reference it by name, e.g.
      via `upsert_identity:`. Members of a composite primary key are still
      flagged: only the key tuple is unique, not the attribute itself.

      This check uses Ash's runtime introspection (`Ash.Resource.Info`) to
      see the fully-resolved attribute and identity lists - including
      contributions from extensions like `AshAuthentication`, which adds an
      `:email` attribute via a transformer that the AST scanner cannot see.
      Migrating to compiled introspection turns this check from "scans the
      source for known attribute names" into "catches concrete missing
      identities on extension-contributed attributes too".

      ## Requirements

      Your project must be compiled before running `mix credo`. If Ash is
      not available in the VM running Credo, the check is a no-op and emits
      a single diagnostic.
      """,
      params: [
        identity_candidates: "Attribute names that should have a uniqueness identity."
      ]
    ]

  alias AshCredo.Introspection
  alias AshCredo.Introspection.Compiled, as: CompiledIntrospection
  alias AshCredo.Orchestration

  @impl AshCredo.CompiledCheck
  def run_compiled(source_file, params) do
    candidates = MapSet.new(Params.get(params, :identity_candidates, __MODULE__))

    Orchestration.flat_map_named_resource(source_file, params, fn resource, context, issue_meta ->
      check_resource(resource, context, candidates, issue_meta)
    end)
  end

  defp check_resource(resource, context, candidates, issue_meta) do
    resource
    |> CompiledIntrospection.inspect_module()
    |> Orchestration.with_resource_info(resource, context, issue_meta, __MODULE__, fn
      %{embedded?: true} -> []
      info -> flag_missing_identities(resource, info, context, candidates, issue_meta)
    end)
  end

  defp flag_missing_identities(
         resource,
         %{attributes: attributes, identities: identities, primary_key: primary_key},
         context,
         candidates,
         issue_meta
       ) do
    covered_fields = collect_identity_fields(identities)
    issue_line = Introspection.resource_issue_line(context)

    attributes
    |> Enum.filter(&(&1.name in candidates))
    |> Enum.reject(&(&1.name in covered_fields or sole_primary_key?(&1, primary_key)))
    |> Enum.map(&missing_identity_issue(&1, resource, issue_line, issue_meta))
  end

  # A sole primary-key attribute is already unique, so no identity is
  # needed for uniqueness enforcement (named identities for e.g.
  # `upsert_identity:` are a deliberate choice, not a lint gap). Members
  # of a composite key stay flagged: only the tuple is unique there.
  defp sole_primary_key?(%{name: name}, primary_key), do: primary_key == [name]

  defp collect_identity_fields(identities) do
    identities
    |> Enum.flat_map(fn identity -> Map.get(identity, :keys) || [] end)
    |> MapSet.new()
  end

  defp missing_identity_issue(attribute, resource, line, issue_meta) do
    format_issue(issue_meta,
      message:
        "Attribute `:#{attribute.name}` on `#{inspect(resource)}` likely needs a uniqueness identity. " <>
          "Add `identity :unique_#{attribute.name}, [:#{attribute.name}]` to the resource's `identities` block.",
      trigger: "#{attribute.name}",
      line_no: line
    )
  end
end
