defmodule Mix.Tasks.Lint.Reach do
  @shortdoc "Runs the Reach lint-grade checks (arch, smells, dead-code)"

  @moduledoc """
  Runs the [Reach](https://github.com/elixir-vibe/reach) checks that are
  deterministic enough to gate `mix lint`:

    * `mix reach.check --arch` against the `.reach.exs` policy
    * `mix reach.check --smells` for cross-function performance smells
    * `mix reach.check --dead-code` for unused pure expressions

  Each mode is invoked as its own `reach.check` run because the task
  picks a single mode per invocation; a single `mix do` alias entry
  would only execute the first one due to Mix's task deduplication.

  The smell mode runs with `--format oneline` so each finding is printed
  as `location: kind: message`. Reach's default smell text output only
  prints a bare count for finding kinds outside its fixed render groups
  (e.g. `trivial_forwarder`), which hid the actual findings.
  """

  use Mix.Task

  @impl true
  def run(_args) do
    run_check(["--arch"])
    run_smells()
    run_check(["--dead-code"])
  end

  defp run_smells do
    # `oneline` prints every finding but omits Reach's section banner, so
    # emit one here to stay consistent with the --arch/--dead-code output.
    Mix.shell().info("\nCross-Function Smell Detection")
    run_check(["--smells", "--format", "oneline"])
  end

  defp run_check(args) do
    Mix.Task.reenable("reach.check")
    Mix.Task.run("reach.check", args)
  end
end
