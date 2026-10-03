defmodule AshCredo.Orchestration do
  @moduledoc """
  Shared helpers for coordinating check execution.

  This module holds Credo-facing plumbing that sits above AST
  introspection, such as iterating resource contexts and building
  `IssueMeta` once per check run before delegating into rule-specific
  logic.
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

  @doc """
  Looks up all same-named DSL section blocks in each resource context,
  flat-mapping each context through `fun.(section_asts, issue_meta)`.
  Spark merges duplicate top-level blocks into one section, so `fun`
  receives the full list (empty when the section is absent).
  """
  def flat_map_resource_section(%SourceFile{} = source_file, params, section_name, fun)
      when is_function(fun, 2) do
    flat_map_resource_context(source_file, params, fn context, issue_meta ->
      context
      |> Introspection.resource_sections(section_name)
      |> fun.(issue_meta)
    end)
  end

  @doc """
  Like `flat_map_resource_section/4`, but also visits
  `Spark.Dsl.Fragment` modules declared `of: Ash.Resource`. A fragment
  holds only part of a resource, so only checks that judge each entity
  on its own may use this; section-level rules such as required entries
  would misfire on fragments.
  """
  def flat_map_resource_or_fragment_section(
        %SourceFile{} = source_file,
        params,
        section_name,
        fun
      )
      when is_function(fun, 2) do
    issue_meta = IssueMeta.for(source_file, params)

    (Introspection.resource_contexts(source_file) ++
       Introspection.resource_fragment_contexts(source_file))
    |> Enum.flat_map(fn context ->
      context
      |> Introspection.resource_sections(section_name)
      |> fun.(issue_meta)
    end)
  end

  @doc """
  Iterates resource contexts and invokes
  `fun.(resource, context, issue_meta)` only for contexts that (a) have
  a literal `defmodule` name, so `:absolute_segments` can resolve to a
  runtime module atom, and (b) declare a non-embedded data layer in
  `use Ash.Resource`. Contexts failing either filter contribute no
  issues.
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
  Iterates resource contexts and invokes
  `fun.(resource, context, issue_meta)` for every context whose
  `defmodule` name is a literal (so `:absolute_segments` resolves to a
  runtime module atom). Unlike `flat_map_loadable_resource/3`, this
  applies no data-layer filter; checks that need one apply their own.
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
  Builds the standard "Ash is not loaded" diagnostic that compiled
  checks emit from the missing branch of
  `Compiled.with_compiled_check/2`. `check` is the emitting check
  module; its short name appears in the message, and its category and
  priority shape the issue via `Credo.Check.format_issue/3`.
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
  Builds one issue per entity in `entities` that does not set `option`,
  either inline or in its `do` block. `message_fun` receives the
  entity's label (see `Introspection.entity_label/1`) and returns the
  issue message; by default it reports a missing explicit option.
  """
  def missing_option_issues(entities, option, issue_meta, check, message_fun \\ nil) do
    message_fun = message_fun || (&"`#{&1}` is missing an explicit `#{option}` option.")

    entities
    |> Enum.reject(&Introspection.entity_has_opt_key?(&1, option))
    |> Enum.map(fn {_call, meta, _args} = entity ->
      Check.format_issue(
        issue_meta,
        [
          message: message_fun.(Introspection.entity_label(entity)),
          trigger: entity_trigger(entity),
          line_no: meta[:line]
        ],
        check
      )
    end)
  end

  # Credo anchors the issue column on the trigger, so it carries the
  # name as written in the source.
  defp entity_trigger({_call, _meta, [name | _]}) when is_atom(name), do: Atom.to_string(name)

  defp entity_trigger({_call, _meta, [name | _]}) when not is_list(name),
    do: Macro.to_string(name)

  defp entity_trigger({call, _meta, _args}), do: Atom.to_string(call)

  @doc """
  Builds the standard "Could not load" diagnostic for `resource`,
  anchored at the context's `use` line and deduplicated to one issue per
  module per run via `Compiled.with_unique_not_loadable/2`. Returns a
  list of zero or one issues.
  """
  def unique_not_loadable_issues(resource, context, issue_meta, check) do
    CompiledIntrospection.with_unique_not_loadable(resource, fn ->
      Check.format_issue(
        issue_meta,
        [
          message:
            "Could not load `#{inspect(resource)}` for `#{short_name(check)}`. " <>
              "Run `mix compile` before `mix credo`, or disable this check in `.credo.exs`.",
          line_no: context.use_line || 1
        ],
        check
      )
    end)
  end

  @doc """
  Dispatches the result of a `Compiled.inspect_module/1`-style
  introspection lookup (`inspect_module/1` itself or any accessor built
  on it, such as `attributes/1` or `actions/1`). Invokes `on_ok.(info)`
  for `{:ok, info}`, emits the deduplicated "could not load" diagnostic
  for `{:error, :not_loadable}`, and contributes no issues for any other
  error.

  Every compiled resource check funnels its lookup result through here,
  so the not-loadable handling lives in one place.
  """
  def with_resource_info(result, resource, context, issue_meta, check, on_ok)
      when is_function(on_ok, 1) do
    case result do
      {:ok, info} -> on_ok.(info)
      {:error, :not_loadable} -> unique_not_loadable_issues(resource, context, issue_meta, check)
      {:error, _} -> []
    end
  end

  defp short_name(check), do: check |> Module.split() |> List.last()
end
