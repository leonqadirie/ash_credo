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

  def flat_map_resource_section(%SourceFile{} = source_file, params, section_name, fun)
      when is_function(fun, 2) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Introspection.resource_contexts()
    |> Enum.flat_map(fn context ->
      context
      |> Introspection.resource_section(section_name)
      |> fun.(issue_meta)
    end)
  end
end
