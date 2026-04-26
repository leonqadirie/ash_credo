defmodule AshCredo.Orchestration do
  @moduledoc """
  Shared helpers for coordinating check execution.

  This module holds Credo-facing plumbing that sits above AST introspection,
  such as iterating resource contexts and building `IssueMeta` once per check
  run before delegating into rule-specific logic.
  """

  alias AshCredo.Introspection
  alias AshCredo.Introspection.ResourceContext
  alias Credo.IssueMeta
  alias Credo.SourceFile

  @doc "Iterates resource contexts in the source file, flat-mapping each through `fun.(context, issue_meta)`."
  def flat_map_resource_context(%SourceFile{} = source_file, params, fun)
      when is_function(fun, 2) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Introspection.resource_contexts()
    |> Enum.flat_map(&fun.(&1, issue_meta))
  end

  @doc "Looks up a DSL section in each resource context, flat-mapping each through `fun.(section_ast, issue_meta)`."
  def flat_map_resource_section(%SourceFile{} = source_file, params, section_name, fun)
      when is_function(fun, 2) do
    flat_map_resource_context(source_file, params, fn context, issue_meta ->
      context
      |> Introspection.resource_section(section_name)
      |> fun.(issue_meta)
    end)
  end

  @doc """
  Iterates resource contexts and invokes `fun.(resource, context, issue_meta)`
  only for contexts that (a) have a literal `defmodule` name (so
  `:absolute_segments` can resolve to a runtime module atom) and (b) declare a
  non-embedded data layer in `use Ash.Resource`. Contexts failing either
  filter contribute no issues.
  """
  def flat_map_loadable_resource(%SourceFile{} = source_file, params, fun)
      when is_function(fun, 3) do
    flat_map_resource_context(source_file, params, fn context, issue_meta ->
      with_loadable_resource(context, fn resource ->
        fun.(resource, context, issue_meta)
      end)
    end)
  end

  defp with_loadable_resource(%ResourceContext{absolute_segments: nil}, _fun), do: []

  defp with_loadable_resource(%ResourceContext{absolute_segments: segments} = context, fun) do
    if Introspection.has_data_layer?(context) do
      fun.(Module.concat(segments))
    else
      []
    end
  end
end
