defmodule AshCredo.Orchestration do
  @moduledoc """
  Shared helpers for coordinating check execution.

  This module holds Credo-facing plumbing that sits above AST introspection,
  such as iterating resource contexts and building `IssueMeta` once per check
  run before delegating into rule-specific logic.
  """

  alias AshCredo.Introspection
  alias AshCredo.Introspection.Compiled, as: CompiledIntrospection
  alias AshCredo.Introspection.ResourceContext
  alias Credo.Check
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

  @doc """
  Iterates resource contexts and invokes `fun.(resource, context, issue_meta)`
  for every context whose `defmodule` name is a literal (so
  `:absolute_segments` resolves to a runtime module atom). Unlike
  `flat_map_loadable_resource/3`, applies no data-layer filter - checks that
  need one apply their own.
  """
  def flat_map_named_resource(%SourceFile{} = source_file, params, fun)
      when is_function(fun, 3) do
    flat_map_resource_context(source_file, params, fn
      %ResourceContext{absolute_segments: nil}, _issue_meta ->
        []

      %ResourceContext{absolute_segments: segments} = context, issue_meta ->
        fun.(Module.concat(segments), context, issue_meta)
    end)
  end

  @doc """
  Full compiled-check harness over named resources: wraps
  `Compiled.with_compiled_check/2` around `flat_map_named_resource/3`,
  emitting the standard Ash-missing diagnostic for `check` when Ash is
  unavailable. Recognized by `SelfCheck.EnforceCompiledCheckWrapper` as
  satisfying the wrapper requirement.
  """
  def compiled_check_on_named_resources(%SourceFile{} = source_file, params, check, fun)
      when is_function(fun, 3) do
    CompiledIntrospection.with_compiled_check(
      fn -> ash_missing_issue(IssueMeta.for(source_file, params), check) end,
      fn -> flat_map_named_resource(source_file, params, fun) end
    )
  end

  @doc """
  Full compiled-check harness over loadable resources: like
  `compiled_check_on_named_resources/4` but iterating via
  `flat_map_loadable_resource/3` (literal name plus non-embedded data
  layer). Recognized by `SelfCheck.EnforceCompiledCheckWrapper` as
  satisfying the wrapper requirement.
  """
  def compiled_check_on_loadable_resources(%SourceFile{} = source_file, params, check, fun)
      when is_function(fun, 3) do
    CompiledIntrospection.with_compiled_check(
      fn -> ash_missing_issue(IssueMeta.for(source_file, params), check) end,
      fn -> flat_map_loadable_resource(source_file, params, fun) end
    )
  end

  @doc """
  Builds the standard "Ash is not loaded" diagnostic that compiled checks
  emit from `Compiled.with_compiled_check/2`'s missing branch. `check` is
  the emitting check module; its short name appears in the message and its
  category/priority shape the issue via `Credo.Check.format_issue/3`.
  """
  def ash_missing_issue(issue_meta, check) do
    Check.format_issue(
      issue_meta,
      [
        message:
          "Ash is not loaded in the VM running Credo - `#{short_name(check)}` is a no-op. " <>
            "Add `:ash` as a dependency, or disable this check in `.credo.exs`.",
        line_no: 1
      ],
      check
    )
  end

  @doc """
  Builds the standard "Could not load" diagnostic for `resource`, anchored
  at the context's `use` line and deduplicated to one issue per module per
  run via `Compiled.with_unique_not_loadable/2`. Returns a list of zero or
  one issues.
  """
  def unique_not_loadable_issues(resource, context, issue_meta, check) do
    CompiledIntrospection.with_unique_not_loadable(resource, fn ->
      Check.format_issue(
        issue_meta,
        [
          message:
            "Could not load `#{inspect(resource)}` for `#{short_name(check)}`. " <>
              "Run `mix compile` before `mix credo`, or disable this check in `.credo.exs`.",
          line_no: Map.get(context, :use_line) || 1
        ],
        check
      )
    end)
  end

  defp short_name(check), do: check |> Module.split() |> List.last()

  @doc """
  Flags bare calls to configured builtin functions at statement position
  inside action bodies, suggesting the given DSL `wrapper` keyword. Shared
  core of `MissingBuiltinWrapper`, which invokes it once per builtin
  family: Ash's builtins are plain functions imported into the DSL scope
  that return spec tuples, so an unwrapped call is silently discarded and
  nothing warns at compile time or runtime.

  `check` is the emitting check module. Required `opts`:

    * `:builtins` - builtin function names to match
    * `:wrapper` - the DSL keyword to suggest (e.g. `"change"`)
    * `:action_types` - action entity types to scan; checks scope this to
      the actions whose scope actually imports their builtin family, so a
      bare call elsewhere is a compile error the compiler already catches

  Optional `opts`:

    * `:pipeline_builtins` - builtin names to also flag at statement
      position inside `pipeline` bodies in the `pipelines` section
      (defaults to `[]`). Pipeline bodies import all three builtin families
      at once, so checks split ownership of names that exist in more than
      one family to avoid double-flagging the same call.
  """
  def naked_builtin_issues(%SourceFile{} = source_file, params, check, opts) do
    builtins = opts |> Keyword.fetch!(:builtins) |> MapSet.new()
    wrapper = Keyword.fetch!(opts, :wrapper)
    action_types = Keyword.fetch!(opts, :action_types)
    pipeline_builtins = opts |> Keyword.get(:pipeline_builtins, []) |> MapSet.new()

    flat_map_resource_context(source_file, params, fn context, issue_meta ->
      action_issues =
        naked_builtin_section_issues(
          context,
          {:actions, action_types, builtins},
          wrapper,
          issue_meta,
          check
        )

      pipeline_issues =
        naked_builtin_section_issues(
          context,
          {:pipelines, [:pipeline], pipeline_builtins},
          wrapper,
          issue_meta,
          check
        )

      action_issues ++ pipeline_issues
    end)
  end

  defp naked_builtin_section_issues(
         context,
         {section_name, entity_names, builtins},
         wrapper,
         issue_meta,
         check
       ) do
    with true <- MapSet.size(builtins) > 0,
         section_ast when not is_nil(section_ast) <-
           Introspection.resource_section(context, section_name) do
      section_ast
      |> Introspection.action_entities(entity_names)
      |> Enum.flat_map(&naked_builtin_calls(&1, builtins, wrapper, issue_meta, check))
    else
      _ -> []
    end
  end

  defp naked_builtin_calls(action_ast, builtins, wrapper, issue_meta, check) do
    action_ast
    |> Introspection.entity_body()
    |> Enum.flat_map(fn
      {func_name, meta, _} ->
        if MapSet.member?(builtins, func_name) do
          [naked_builtin_issue(func_name, wrapper, meta, issue_meta, check)]
        else
          []
        end

      _ ->
        []
    end)
  end

  defp naked_builtin_issue(func_name, wrapper, meta, issue_meta, check) do
    Check.format_issue(
      issue_meta,
      [
        message:
          "`#{func_name}` has no effect without a `#{wrapper}` wrapper. " <>
            "Use `#{wrapper} #{func_name}(...)` instead.",
        trigger: "#{func_name}",
        line_no: meta[:line]
      ],
      check
    )
  end
end
