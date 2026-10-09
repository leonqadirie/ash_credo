# Per-check cost with an empty cache: each check pays for any shared walk
# it triggers. Ranks checks to find hot spots.
#
#     MIX_ENV=test mix run bench/checks.exs
#
# `BENCH_CHECKS=RaisingCall,UnknownAction` times only those checks, on every
# input including `large`, and saves under a suite name of its own so it
# never mixes with full runs in a comparison.

alias Bench.Helper

Code.require_file("support/bench_helper.exs", __DIR__)

{checks, suite, inputs} =
  case Helper.selected_checks() do
    :all ->
      {Helper.checks(), "checks", Helper.inputs(["fixtures", "medium"])}

    selected ->
      names = selected |> Enum.map(&Helper.short_name/1) |> Enum.sort()
      {selected, Enum.join(["checks" | names], "+"), Helper.inputs()}
  end

Helper.preflight!(inputs)

jobs = Map.new(checks, fn check -> {Helper.check_name(check), &Helper.run_check(check, &1)} end)

Benchee.run(
  jobs,
  Helper.run_opts(suite,
    timing: {0.5, 1},
    inputs: inputs,
    before_each: fn source_file ->
      Helper.cold!()
      source_file
    end
  )
)
