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

      A composite primary key assembled from `belongs_to ..., primary_key?: true`
      relationships counts too, as does a primary key contributed by a
      `Spark.Dsl.Fragment` or by an extension (e.g. `AshEventLog.EventLog`).

      This check reads Ash's runtime introspection
      (`Ash.Resource.Info.primary_key/1`) to see the fully-resolved primary
      key, so keys spliced in via fragments or added by extension
      transformers are recognised - not just the ones declared lexically in
      the resource's own `attributes`/`relationships` blocks.

      ## Requirements

      Your project must be compiled before running `mix credo`. If Ash is
      not available in the VM running Credo, the check is a no-op and emits
      a single diagnostic.

      ## Notes

      A resource counts as "backed by a data layer" only when it declares a
      non-embedded `data_layer:` in its own `use Ash.Resource` call. A data
      layer contributed entirely by a fragment or extension is not detected
      here, so such a resource is skipped - the same AST-level gate every
      compiled check shares.

      Resources that Ash itself does not require a primary key for are not
      flagged either: those that opt out with `require_primary_key? false`,
      and those that expose only generic actions and have no fields. This
      mirrors `Ash.Resource.Verifiers.VerifyPrimaryKeyPresent`.
      """
    ]

  alias AshCredo.Introspection
  alias AshCredo.Introspection.Compiled, as: CompiledIntrospection
  alias AshCredo.Introspection.ResourceContext
  alias AshCredo.Orchestration

  @impl true
  def run(%SourceFile{} = source_file, params) do
    CompiledIntrospection.with_compiled_check(
      fn ->
        format_issue(IssueMeta.for(source_file, params),
          message:
            "Ash is not loaded in the VM running Credo - `MissingPrimaryKey` is a no-op. Add `:ash` as a dependency, or disable this check in `.credo.exs`.",
          line_no: 1
        )
      end,
      fn ->
        Orchestration.flat_map_loadable_resource(source_file, params, &check_loaded_resource/3)
      end
    )
  end

  defp check_loaded_resource(
         resource,
         %ResourceContext{module_ast: module_ast} = context,
         issue_meta
       ) do
    case CompiledIntrospection.primary_key(resource) do
      {:ok, [_ | _]} ->
        []

      {:ok, []} ->
        if CompiledIntrospection.primary_key_optional?(resource) do
          []
        else
          [missing_primary_key_issue(module_ast, context, issue_meta)]
        end

      {:error, :not_loadable} ->
        CompiledIntrospection.with_unique_not_loadable(resource, fn ->
          not_loadable_issue(resource, context, issue_meta)
        end)

      {:error, _} ->
        []
    end
  end

  defp missing_primary_key_issue(module_ast, context, issue_meta) do
    attrs_ast = Introspection.find_dsl_section(module_ast, :attributes)

    format_issue(issue_meta,
      message: "Resource is missing a primary key.",
      trigger: "attributes",
      line_no: Introspection.resource_issue_line(context, attrs_ast)
    )
  end

  defp not_loadable_issue(resource, context, issue_meta) do
    format_issue(issue_meta,
      message:
        "Could not load `#{inspect(resource)}` for `MissingPrimaryKey`. Run `mix compile` before `mix credo`, or disable this check in `.credo.exs`.",
      line_no: Map.get(context, :use_line) || 1
    )
  end
end
