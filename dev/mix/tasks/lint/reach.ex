defmodule Mix.Tasks.Lint.Reach do
  @shortdoc "Runs the Reach lint-grade checks (arch, smells, dead-code)"

  @moduledoc """
  Runs the [Reach](https://github.com/elixir-vibe/reach) checks that are
  deterministic enough to gate `mix lint`. Each one fails the task on any
  finding:

    * `mix reach.check --arch` against the `.reach.exs` policy
    * `mix reach.check --smells` for cross-function performance smells;
      `.reach.exs` sets `smells: [strict: true]` so findings fail the run
    * `Reach.Check.DeadCode` for unused pure expressions

  The arch and smell modes are invoked as separate `reach.check` runs
  because the task picks a single mode per invocation; a single `mix do`
  alias entry would only execute the first one due to Mix's task
  deduplication.

  The task calls `Reach.Check.DeadCode` directly because
  `reach.check --dead-code` only prints its findings and never fails.

  The smell mode runs with `--format oneline` so each finding is printed
  as `location: kind: message`. Reach's default smell text output only
  prints a bare count for finding kinds outside its fixed render groups
  (e.g. `trivial_forwarder`), which hid the actual findings.
  """

  use Mix.Task

  alias Reach.Check.DeadCode

  @impl true
  def run(_args) do
    run_check(["--arch"])
    run_smells()
    run_dead_code()
  end

  defp run_smells do
    # `oneline` prints every finding but omits Reach's section banner, so
    # emit one here to stay consistent with the --arch/--dead-code output.
    Mix.shell().info("\nCross-Function Smell Detection")
    run_check(["--smells", "--format", "oneline"])
  end

  defp run_dead_code do
    Mix.shell().info("\nDead Code")

    case DeadCode.run(DeadCode.collect_files(["lib", "dev"])) do
      [] ->
        Mix.shell().info("  (none)")

      findings ->
        Enum.each(findings, fn finding ->
          Mix.shell().info(
            "#{finding.file}:#{finding.line}: #{finding.kind}: #{finding.description}"
          )
        end)

        Mix.raise("Reach found #{length(findings)} dead code finding(s)")
    end
  end

  defp run_check(args), do: Mix.Task.rerun("reach.check", args)
end
