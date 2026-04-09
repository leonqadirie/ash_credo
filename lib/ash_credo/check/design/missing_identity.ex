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
      see the fully-resolved attribute and identity lists — including
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

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    candidates = MapSet.new(Params.get(params, :identity_candidates, __MODULE__))

    CompiledIntrospection.with_compiled_check(
      fn ->
        format_issue(issue_meta,
          message:
            "Ash is not loaded in the VM running Credo — `MissingIdentity` is a no-op. Add `:ash` as a dependency, or disable this check in `.credo.exs`.",
          line_no: 1
        )
      end,
      fn ->
        source_file
        |> Introspection.resource_contexts()
        |> Enum.flat_map(&check_resource(&1, candidates, issue_meta))
      end
    )
  end

  defp check_resource(%{absolute_segments: nil}, _candidates, _issue_meta), do: []

  defp check_resource(%{absolute_segments: segments} = context, candidates, issue_meta) do
    resource = Module.concat(segments)

    case CompiledIntrospection.inspect_module(resource) do
      {:ok, info} ->
        flag_missing_identities(resource, info, context, candidates, issue_meta)

      {:error, :not_loadable} ->
        [not_loadable_issue(resource, context, issue_meta)]

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

  defp not_loadable_issue(resource, context, issue_meta) do
    format_issue(issue_meta,
      message:
        "Could not load `#{inspect(resource)}` for `MissingIdentity`. Run `mix compile` before `mix credo`, or disable this check in `.credo.exs`.",
      line_no: Map.get(context, :use_line) || 1
    )
  end
end
