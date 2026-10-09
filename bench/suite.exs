# All checks over one file, as a Credo run executes them. `suite_cold`
# starts each iteration with an empty cache, so the first check pays for the
# shared walks; `suite_warm` reuses a filled cache. The difference is the
# cost of the memoized walks; `suite_warm` alone is the uncached floor.
#
#     MIX_ENV=test mix run bench/suite.exs

alias Bench.Helper

Code.require_file("support/bench_helper.exs", __DIR__)

inputs = Helper.inputs()
Helper.preflight!(inputs)

Helper.run!(
  "suite",
  %{
    "suite_cold" => {&Helper.run_all/1, before_each: &Helper.cold/1},
    "suite_warm" =>
      {&Helper.run_all/1,
       before_scenario: fn source_file ->
         Helper.cold!()
         Helper.run_all(source_file)
         source_file
       end}
  },
  timing: {1, 3},
  inputs: inputs,
  memory_time: 0.5,
  reduction_time: 0.5
)
