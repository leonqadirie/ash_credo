defmodule AshCredo.Check.Warning.MissingValidationWrapper do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:ash],
    explanations: [
      check: """
      Builtin validation functions like `present`, `attribute_equals`, and
      `compare` must be wrapped in `validate` when used inside an action body.

      These builtins are plain functions imported into the DSL scope. Without
      the wrapper, the call returns a validation spec tuple that is silently
      discarded - the validation never runs, unvalidated input passes
      through, and no error or warning is raised at compile time or runtime.

          # Bad - compiles but the validation never runs
          create :register do
            accept [:email]
            present(:email)
          end

          # Good - wrapped in validate
          create :register do
            accept [:email]
            validate present(:email)
          end

      The same trap exists inside `pipeline` bodies (the `pipelines`
      section), which import the validation builtins too - bare calls there
      are flagged as well.

      Because some builtin names are common words (`present`, `compare`,
      `match`), a bare call to a same-named local helper inside an action
      body would be flagged too; silence such a call with
      `# credo:disable-for-next-line`. `Warning.MissingChangeWrapper` and
      `Warning.MissingPrepareWrapper` are the equivalent checks for change
      and preparation builtins.
      """
    ]

  alias AshCredo.Orchestration

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

  # Includes :read - read actions import Ash.Resource.Validation.Builtins
  # and accept `validate` entities, so they carry the same trap.
  @action_types ~w(create read update destroy action)a

  @impl true
  def run(%SourceFile{} = source_file, params) do
    Orchestration.naked_builtin_issues(source_file, params, __MODULE__,
      builtins: @validation_builtins,
      wrapper: "validate",
      action_types: @action_types,
      pipeline_builtins: @validation_builtins
    )
  end
end
