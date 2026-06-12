defmodule AshCredo.Check.Warning.MissingChangeWrapper do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:ash],
    explanations: [
      check: """
      Builtin change functions like `manage_relationship`, `set_attribute`, and
      `relate_actor` must be wrapped in `change` when used inside an action body.

      These builtins are plain functions imported into the DSL scope. Without
      the wrapper, the call returns a change spec tuple that is silently
      discarded - the change never runs and no error or warning is raised at
      compile time or runtime.

          # Bad - compiles but silently does nothing
          create :some_action do
            argument :thing, :map
            manage_relationship(:thing, :thing, type: :create)
          end

          # Good - wrapped in change
          create :some_action do
            argument :thing, :map
            change manage_relationship(:thing, :thing, type: :create)
          end

      The same trap exists inside `pipeline` bodies (the `pipelines`
      section), which import the change builtins too - bare calls there are
      flagged as well.

      `Warning.MissingValidationWrapper` and `Warning.MissingPrepareWrapper`
      are the equivalent checks for validation and preparation builtins.
      """
    ]

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

  # No :read or :action - those import only the Preparation and Validation
  # builtins, so a bare change builtin there fails to compile and needs no
  # lint. The one change builtin that does compile bare in a generic action
  # is `set_context` (via its Ash.Resource.Preparation.Builtins twin) - it
  # belongs to MissingPrepareWrapper there, because generic actions take
  # `prepare`, not `change`.
  @action_types ~w(create update destroy)a

  @impl true
  def run(%SourceFile{} = source_file, params) do
    Orchestration.naked_builtin_issues(source_file, params, __MODULE__,
      builtins: @change_builtins,
      wrapper: "change",
      action_types: @action_types,
      # Pipeline bodies import all builtin families, including the changes;
      # the ambiguous `set_context` is owned by this check there, since
      # pipelines accept `change` entities.
      pipeline_builtins: @change_builtins
    )
  end
end
