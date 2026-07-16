defmodule AshCredo.Check.Refactor.AnonymousFunctionInDsl do
  use Credo.Check,
    base_priority: :normal,
    category: :refactor,
    tags: [:ash],
    explanations: [
      check: """
      Flags anonymous functions (`fn ... end` or `&...` captures) passed to
      `change`, `validate`, `prepare`, or `calculate` in the resource DSL.
      Prefer to put the code in its own module and refer to that instead.

      For changes and validations this is more than style: anonymous
      functions can never participate in atomic execution, because Ash
      cannot inspect what they contain. An update or destroy action
      carrying one either fails its atomicity requirement at runtime or
      forces `require_atomic? false`. Anonymous function changes also
      cannot support batching. Function captures compile to the same
      `*.Function` wrapper as `fn` and carry the same limitation.

          # Bad - can never be atomic, forces require_atomic? false
          update :update do
            change fn changeset, _context ->
              Ash.Changeset.force_change_attribute(changeset, :slug, slug())
            end
          end

          # Good - module callback, can implement atomic/3
          update :update do
            change MyApp.Changes.SlugifyName
          end

      Calculations have the equivalent limitation through `expression/2`:
      an anonymous function calculation can never supply an expression, so
      the data layer cannot run it and sorting on it raises an
      `UndefinedFunctionError` at runtime. A module using
      `Ash.Resource.Calculation` can implement `expression/2`; an `expr(...)`
      calculation is data-layer-native and is not flagged.

      Anonymous functions are fine for prototyping, which is why this
      check is opt-in; silence individual call sites with
      `# credo:disable-for-next-line`.
      """
    ]

  alias AshCredo.Introspection
  alias AshCredo.Orchestration

  @wrappers ~w(change validate prepare)a
  @action_types ~w(create read update destroy action)a

  # Sections whose direct entries are change/validate/prepare entities.
  @entity_sections ~w(changes validations preparations)a

  @module_advice %{
    change:
      "anonymous function changes can never be made atomic or support batching. " <>
        "Extract it into a module with `use Ash.Resource.Change`",
    validate:
      "anonymous function validations can never be made atomic. " <>
        "Extract it into a module with `use Ash.Resource.Validation`",
    prepare: "Extract it into a module with `use Ash.Resource.Preparation`",
    calculate:
      "anonymous function calculations can never supply an expression, so the data " <>
        "layer cannot run them and sorting on them raises at runtime. Extract it into a " <>
        "module with `use Ash.Resource.Calculation` (which can implement `expression/2`) " <>
        "or use `expr(...)`"
  }

  @impl true
  def run(%SourceFile{} = source_file, params) do
    Orchestration.flat_map_resource_context(source_file, params, fn context, issue_meta ->
      action_issues(context, issue_meta) ++
        entity_section_issues(context, issue_meta) ++
        pipeline_issues(context, issue_meta) ++
        calculation_issues(context, issue_meta)
    end)
  end

  defp action_issues(context, issue_meta) do
    entity_body_issues(context, :actions, @action_types, issue_meta)
  end

  defp pipeline_issues(context, issue_meta) do
    entity_body_issues(context, :pipelines, [:pipeline], issue_meta)
  end

  defp entity_body_issues(context, section_name, entity_names, issue_meta) do
    context
    |> Introspection.resource_sections(section_name)
    |> Introspection.action_entities(entity_names)
    |> Enum.flat_map(fn entity_ast ->
      entity_ast
      |> Introspection.entity_body()
      |> Enum.flat_map(&anonymous_wrapper_issues(&1, issue_meta))
    end)
  end

  defp entity_section_issues(context, issue_meta) do
    Enum.flat_map(@entity_sections, fn section_name ->
      context
      |> Introspection.resource_sections(section_name)
      |> Introspection.action_entities(@wrappers)
      |> Enum.flat_map(&anonymous_wrapper_issues(&1, issue_meta))
    end)
  end

  # The callback is `calculate`'s third positional argument
  # (`calculate :name, :type, fn ... end`), unlike the wrappers, where it
  # is the first.
  defp calculation_issues(context, issue_meta) do
    context
    |> Introspection.resource_sections(:calculations)
    |> Introspection.action_entities([:calculate])
    |> Enum.flat_map(&calculate_entity_issues(&1, issue_meta))
  end

  defp calculate_entity_issues(
         {:calculate, meta, [_name, _type, calculation | _]} = entity_ast,
         issue_meta
       ) do
    if anonymous_function?(calculation) do
      [anonymous_issue(:calculate, meta, issue_meta)]
    else
      do_block_calculation_issues(entity_ast, issue_meta)
    end
  end

  defp calculate_entity_issues(entity_ast, issue_meta) do
    do_block_calculation_issues(entity_ast, issue_meta)
  end

  defp do_block_calculation_issues(entity_ast, issue_meta) do
    entity_ast
    |> Introspection.entity_body()
    |> Enum.flat_map(fn
      {:calculation, meta, [calculation | _]} ->
        if anonymous_function?(calculation) do
          [anonymous_issue(:calculate, meta, issue_meta)]
        else
          []
        end

      _other ->
        []
    end)
  end

  defp anonymous_wrapper_issues({wrapper, meta, [first_arg | _]}, issue_meta)
       when wrapper in @wrappers do
    if anonymous_function?(first_arg) do
      [anonymous_issue(wrapper, meta, issue_meta)]
    else
      []
    end
  end

  defp anonymous_wrapper_issues(_other, _issue_meta), do: []

  defp anonymous_issue(wrapper, meta, issue_meta) do
    format_issue(issue_meta,
      message: "`#{wrapper}` is passed an anonymous function - #{@module_advice[wrapper]}.",
      trigger: "#{wrapper}",
      line_no: meta[:line]
    )
  end

  defp anonymous_function?({:fn, _, _}), do: true
  defp anonymous_function?({:&, _, _}), do: true
  defp anonymous_function?(_other), do: false
end
