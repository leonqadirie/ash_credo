# Per-check cost with an empty cache: each check pays for any shared walk
# it triggers. Ranks checks to find hot spots.
#
#     MIX_ENV=test mix run bench/checks.exs

alias Bench.Helper

Code.require_file("support/bench_helper.exs", __DIR__)

inputs = Helper.inputs(["fixtures", "medium"])
Helper.preflight!(inputs)

jobs =
  Map.new(Helper.checks(), fn check ->
    name = check |> inspect() |> String.replace_prefix("AshCredo.Check.", "")
    {name, &Helper.run_check(check, &1)}
  end)

Benchee.run(
  jobs,
  Helper.run_opts("checks",
    timing: {0.5, 1},
    inputs: inputs,
    before_each: fn source_file ->
      Helper.cold!()
      source_file
    end
  )
)
