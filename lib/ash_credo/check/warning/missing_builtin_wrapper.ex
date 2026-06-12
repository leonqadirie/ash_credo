defmodule AshCredo.Check.Warning.MissingBuiltinWrapper do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:ash],
    explanations: [
      check: """
      Builtin change, validation, and preparation functions like
      `set_attribute`, `present`, and `build` must be wrapped in their DSL
      keyword (`change`, `validate`, `prepare`) when used inside an action
      body or a `pipeline` body.

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
  #     take `prepare`, not `change`.
  #   * validations - includes :read: read actions import
  #     Ash.Resource.Validation.Builtins and accept `validate` entities.
  #   * preparations - only :read and :action import
  #     Ash.Resource.Preparation.Builtins.
  #
  # Pipeline bodies import all three families at once; the ambiguous
  # `set_context` is owned by the changes family there, since pipelines
  # accept `change` entities.
  @families [
    [
      builtins: @change_builtins,
      wrapper: "change",
      action_types: ~w(create update destroy)a,
      pipeline_builtins: @change_builtins
    ],
    [
      builtins: @validation_builtins,
      wrapper: "validate",
      action_types: ~w(create read update destroy action)a,
      pipeline_builtins: @validation_builtins
    ],
    [
      builtins: @preparation_builtins,
      wrapper: "prepare",
      action_types: ~w(read action)a,
      pipeline_builtins: ~w(build)a
    ]
  ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    Enum.flat_map(@families, fn family ->
      Orchestration.naked_builtin_issues(source_file, params, __MODULE__, family)
    end)
  end
end
