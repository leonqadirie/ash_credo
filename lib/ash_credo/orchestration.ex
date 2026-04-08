defmodule AshCredo.Orchestration do
  @moduledoc """
  Shared helpers for coordinating check execution.

  This module holds Credo-facing plumbing that sits above AST introspection,
  such as iterating resource contexts and building `IssueMeta` once per check
  run before delegating into rule-specific logic.
  """

  alias AshCredo.Introspection
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
end
