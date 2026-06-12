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

  @impl true
  def run(%SourceFile{} = source_file, params) do
    candidates = MapSet.new(Params.get(params, :identity_candidates, __MODULE__))

    Orchestration.compiled_check_on_named_resources(
      source_file,
      params,
      __MODULE__,
      fn resource, context, issue_meta ->
        check_resource(resource, context, candidates, issue_meta)
      end
    )
  end

  defp check_resource(resource, context, candidates, issue_meta) do
    if CompiledIntrospection.embedded?(resource) do
      []
    else
      inspect_resource(resource, context, candidates, issue_meta)
    end
  end

  defp inspect_resource(resource, context, candidates, issue_meta) do
    case CompiledIntrospection.inspect_module(resource) do
      {:ok, info} ->
        flag_missing_identities(resource, info, context, candidates, issue_meta)

      {:error, :not_loadable} ->
        Orchestration.unique_not_loadable_issues(resource, context, issue_meta, __MODULE__)

      {:error, _} ->
        []
    end
  end

  defp flag_missing_identities(
         resource,
         %{attributes: attributes, identities: identities},
         context,
         candidates,
         issue_meta
       ) do
    covered_fields = collect_identity_fields(identities)
    issue_line = Introspection.resource_issue_line(context)

    attributes
    |> Enum.filter(&(&1.name in candidates))
    |> Enum.reject(&(&1.name in covered_fields))
    |> Enum.map(&missing_identity_issue(&1, resource, issue_line, issue_meta))
  end

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
