defmodule AshCredo.CompiledCheck do
  @moduledoc """
  Base for checks that introspect compiled Ash modules.

  `use AshCredo.CompiledCheck` injects `use Credo.Check` (passing every option
  through unchanged) and a generated `run/2` that guards every invocation with
  the Ash-availability check. When Ash is not loaded in the VM running Credo,
  the check emits a single informational diagnostic - once per run, across all
  compiled checks - and runs no introspection; otherwise it delegates to the
  check's `run_compiled/2` callback.

  This makes the wrapper structural rather than a convention. A compiled check
  cannot run introspection without the guard, so it can never raise or silently
  no-op when the host project is not compiled, and there is no wrapper call to
  forget.

  Implement `run_compiled/2`. Optionally override `active?/2` to skip the check
  entirely - producing no issues and no ash-missing diagnostic - before the
  guard runs; use it for checks disabled by path filters or configuration, so
  a disabled check stays silent even when Ash is unavailable.
  """

  alias AshCredo.Introspection.Compiled, as: CompiledIntrospection
  alias AshCredo.Orchestration
  alias Credo.IssueMeta
  alias Credo.SourceFile

  @doc """
  Runs the check body. Invoked only when `active?/2` returns `true` and Ash is
  available in the VM. Returns the list of issues.
  """
  @callback run_compiled(SourceFile.t(), keyword()) :: [Credo.Issue.t()]

  @doc """
  Whether the check should run for this file and params at all. When `false`,
  the check produces no issues and no ash-missing diagnostic. Defaults to
  `true`.
  """
  @callback active?(SourceFile.t(), keyword()) :: boolean()

  @optional_callbacks active?: 2

  defmacro __using__(opts) do
    quote do
      @behaviour AshCredo.CompiledCheck

      use Credo.Check, unquote(opts)

      @impl Credo.Check
      def run(%SourceFile{} = source_file, params),
        do: AshCredo.CompiledCheck.run_guarded(__MODULE__, source_file, params)

      @impl AshCredo.CompiledCheck
      def active?(_source_file, _params), do: true

      defoverridable active?: 2
    end
  end

  @doc false
  def run_guarded(check, %SourceFile{} = source_file, params) do
    if check.active?(source_file, params) do
      CompiledIntrospection.with_compiled_check(
        fn -> Orchestration.ash_missing_issue(IssueMeta.for(source_file, params), check) end,
        fn -> check.run_compiled(source_file, params) end
      )
    else
      []
    end
  end
end
