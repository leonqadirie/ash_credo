defmodule AshCredo.Check.Warning.MissingBuiltinWrapper do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:ash],
    explanations: [
      check: """
      Builtin change, validation, preparation, and calculation functions
      like `set_attribute`, `present`, `build`, and `concat` must be
      wrapped in their DSL entity (`change`, `validate`, `prepare`,
      `calculate ...`) when used inside an action body, a `pipeline` body,
      or a global section (`changes`, `validations`, `preparations`,
      `calculations`).

      These builtins are plain functions imported into the DSL scope.
      Without the wrapper, the call returns a spec tuple that is silently
      discarded - the change/validation/preparation never runs and no error
      or warning is raised at compile time or runtime.

          # Bad - compiles but silently does nothing
          create :register do
            accept [:email]
            present(:email)
            set_attribute(:status, :draft)
          end

          # Good - wrapped in the matching keyword
          create :register do
            accept [:email]
            validate present(:email)
            change set_attribute(:status, :draft)
          end

      Each builtin family is only checked in the scopes that import it, so
      a bare call the compiler already rejects is never flagged. The advice
      is position-aware for `set_context`, which exists as both a change
      and a preparation builtin: in pipelines it gets `change`, in read and
      generic actions `prepare`.

      Because some builtin names are common words (`present`, `compare`,
      `match`, `build`), a bare call to a same-named local helper inside an
      action body would be flagged too; silence such a call with
      `# credo:disable-for-next-line`.
      """
    ]

  alias AshCredo.Introspection
  alias AshCredo.Orchestration

  @change_builtins ~w(
    manage_relationship
    relate_actor
    set_attribute
    set_new_attribute
    set_context
    atomic_set
    atomic_update
    increment
    cascade_destroy
    cascade_update
    optimistic_lock
    prevent_change
    ensure_selected
    get_and_lock
    get_and_lock_for_update
    debug_log
  )a

  @validation_builtins ~w(
    absent
    action_is
    any
    argument_does_not_equal
    argument_equals
    argument_in
    attribute_does_not_equal
    attribute_equals
    attribute_in
    attributes_absent
    attributes_present
    byte_size
    changing
    compare
    confirm
    data_one_of
    match
    negate
    numericality
    one_of
    pre_flight_authorization
    present
    string_length
  )a

  @preparation_builtins ~w(build set_context)a

  # One entry per builtin family; each is scoped to the scopes that actually
  # import it, so a bare call anywhere else is a compile error the compiler
  # already catches:
  #
  #   * changes - no :read or :action: those import only the Preparation and
  #     Validation builtins. The one change builtin that compiles bare in a
  #     generic action is `set_context` (via its Preparation.Builtins twin),
  #     which the preparations family owns there, because generic actions
  #     take `prepare`, not `change`. The `changes` global section imports
  #     Change.Builtins (and Validation.Builtins), so the changes family
  #     owns `set_context` there too.
  #   * validations - includes :read: read actions import
  #     Ash.Resource.Validation.Builtins and accept `validate` entities. All
  #     three global sections import Validation.Builtins.
  #   * preparations - only :read and :action import
  #     Ash.Resource.Preparation.Builtins; among the global sections, only
  #     `preparations` does (so `set_context` is unambiguous there).
  #   * calculations - the `calculations` section imports
  #     Ash.Resource.Calculation.Builtins (just `concat`); the fix is a full
  #     `calculate` entity, reflected in the usage_prefix.
  #
  # Pipeline bodies import the change/validation/preparation families at
  # once (but NOT the calculation builtins - a bare `concat` there is a
  # compile error); the ambiguous `set_context` is owned by the changes
  # family in pipelines, since they accept `change` entities.
  @families [
    [
      builtins: @change_builtins,
      wrapper: "change",
      action_types: ~w(create update destroy)a,
      pipeline_builtins: @change_builtins,
      global_sections: [:changes]
    ],
    [
      builtins: @validation_builtins,
      wrapper: "validate",
      action_types: ~w(create read update destroy action)a,
      pipeline_builtins: @validation_builtins,
      global_sections: [:validations, :changes, :preparations]
    ],
    [
      builtins: @preparation_builtins,
      wrapper: "prepare",
      action_types: ~w(read action)a,
      pipeline_builtins: ~w(build)a,
      global_sections: [:preparations]
    ],
    [
      builtins: ~w(concat)a,
      wrapper: "calculate",
      action_types: [],
      global_sections: [:calculations],
      usage_prefix: "calculate :name, :type, "
    ]
  ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    Enum.flat_map(@families, fn family ->
      naked_builtin_issues(source_file, params, family)
    end)
  end

  # Flags bare calls to configured builtin functions at statement position
  # inside action bodies, `pipeline` bodies, and global sections, suggesting
  # the matching DSL wrapper keyword. Ash's builtins are plain functions
  # imported into the DSL scope that return spec tuples, so an unwrapped call
  # is silently discarded and nothing warns at compile time or runtime.
  #
  # Required `opts`:
  #
  #   * `:builtins` - builtin function names to match
  #   * `:wrapper` - the DSL keyword to suggest (e.g. `"change"`)
  #   * `:action_types` - action entity types to scan; scoped to the actions
  #     whose scope actually imports their builtin family, so a bare call
  #     elsewhere is a compile error the compiler already catches
  #
  # Optional `opts`:
  #
  #   * `:pipeline_builtins` - builtin names to also flag at statement position
  #     inside `pipeline` bodies (defaults to `[]`). Pipeline bodies import all
  #     three builtin families at once, so families split ownership of names
  #     that exist in more than one family to avoid double-flagging.
  #   * `:global_sections` - top-level DSL sections (e.g. `:validations`) whose
  #     direct entries are scanned for bare builtin calls (defaults to `[]`).
  #   * `:usage_prefix` - what to put before `builtin(...)` in the advice
  #     (defaults to `"<wrapper> "`).
  defp naked_builtin_issues(source_file, params, opts) do
    builtins = opts |> Keyword.fetch!(:builtins) |> MapSet.new()
    wrapper = Keyword.fetch!(opts, :wrapper)
    action_types = Keyword.fetch!(opts, :action_types)
    pipeline_builtins = opts |> Keyword.get(:pipeline_builtins, []) |> MapSet.new()
    global_sections = Keyword.get(opts, :global_sections, [])
    advice = {wrapper, Keyword.get(opts, :usage_prefix, "#{wrapper} ")}

    Orchestration.flat_map_resource_context(source_file, params, fn context, issue_meta ->
      action_issues =
        naked_builtin_section_issues(
          context,
          {:actions, action_types, builtins},
          advice,
          issue_meta
        )

      pipeline_issues =
        naked_builtin_section_issues(
          context,
          {:pipelines, [:pipeline], pipeline_builtins},
          advice,
          issue_meta
        )

      global_issues =
        Enum.flat_map(
          global_sections,
          &naked_global_section_issues(context, &1, builtins, advice, issue_meta)
        )

      action_issues ++ pipeline_issues ++ global_issues
    end)
  end

  defp naked_global_section_issues(context, section_name, builtins, advice, issue_meta) do
    case Introspection.resource_section(context, section_name) do
      nil -> []
      section_ast -> naked_builtin_calls(section_ast, builtins, advice, issue_meta)
    end
  end

  defp naked_builtin_section_issues(
         context,
         {section_name, entity_names, builtins},
         advice,
         issue_meta
       ) do
    with true <- MapSet.size(builtins) > 0,
         section_ast when not is_nil(section_ast) <-
           Introspection.resource_section(context, section_name) do
      section_ast
      |> Introspection.action_entities(entity_names)
      |> Enum.flat_map(&naked_builtin_calls(&1, builtins, advice, issue_meta))
    else
      _ -> []
    end
  end

  # Works on any AST node with a do-block whose direct entries are statements:
  # action entities, pipeline entities, and global sections.
  defp naked_builtin_calls(ast, builtins, advice, issue_meta) do
    for {func_name, meta, _} <- Introspection.entity_body(ast),
        MapSet.member?(builtins, func_name) do
      naked_builtin_issue(func_name, advice, meta, issue_meta)
    end
  end

  defp naked_builtin_issue(func_name, {wrapper, usage_prefix}, meta, issue_meta) do
    format_issue(
      issue_meta,
      message:
        "`#{func_name}` has no effect without a `#{wrapper}` wrapper. " <>
          "Use `#{usage_prefix}#{func_name}(...)` instead.",
      trigger: "#{func_name}",
      line_no: meta[:line]
    )
  end
end
