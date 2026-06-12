defmodule AshCredo.Check.Warning.MissingPrepareWrapper do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:ash],
    explanations: [
      check: """
      Builtin preparation functions (`build`, `set_context`) must be wrapped
      in `prepare` when used inside a read or generic action body.

      These builtins are plain functions imported into the DSL scope. Without
      the wrapper, the call returns a preparation spec tuple that is silently
      discarded - the preparation never runs and no error or warning is
      raised at compile time or runtime.

          # Bad - compiles but the preparation never runs
          read :recent do
            build(sort: [inserted_at: :desc])
          end

          # Good - wrapped in prepare
          read :recent do
            prepare build(sort: [inserted_at: :desc])
          end

      The same trap exists inside `pipeline` bodies (the `pipelines`
      section), which import the preparation builtins too - a bare `build`
      there is flagged as well. A bare `set_context` in a pipeline is
      reported by `Warning.MissingChangeWrapper` instead, because pipelines
      accept `change` entities and the name exists in both builtin families.

      Because `build` is a common word, a bare call to a same-named local
      helper inside an action body would be flagged too; silence such a
      call with `# credo:disable-for-next-line`.
      `Warning.MissingChangeWrapper` and `Warning.MissingValidationWrapper`
      are the equivalent checks for change and validation builtins.
      """
    ]

  alias AshCredo.Orchestration

  @preparation_builtins ~w(build set_context)a

  # Only :read and :action import Ash.Resource.Preparation.Builtins; a bare
  # preparation builtin in create/update/destroy fails to compile and needs
  # no lint.
  @action_types ~w(read action)a

  # Pipeline bodies import the change builtins alongside the preparations,
  # making a bare `set_context` ambiguous there; MissingChangeWrapper owns
  # it in pipelines, so only the unambiguous `build` is flagged here.
  @pipeline_builtins ~w(build)a

  @impl true
  def run(%SourceFile{} = source_file, params) do
    Orchestration.naked_builtin_issues(source_file, params, __MODULE__,
      builtins: @preparation_builtins,
      wrapper: "prepare",
      action_types: @action_types,
      pipeline_builtins: @pipeline_builtins
    )
  end
end
