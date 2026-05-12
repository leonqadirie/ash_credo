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
  """

  use Mix.Task

  @modes ["--arch", "--smells", "--dead-code"]

  @impl true
  def run(_args) do
    Enum.each(@modes, fn mode ->
      Mix.Task.reenable("reach.check")
      Mix.Task.run("reach.check", [mode])
    end)
  end
end
