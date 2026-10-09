# The memoized whole-file walks in isolation, each with an empty cache.
# `resource_contexts` runs the LexicalScopeWalker traversal behind
# `module_metadata`; `sites` includes compiled resolution on top of the
# call scan.
#
#     MIX_ENV=test mix run bench/walks.exs

alias AshCredo.Introspection
alias AshCredo.Introspection.{AshCallResolver, AshCallScanner}
alias Bench.Helper

Code.require_file("support/bench_helper.exs", __DIR__)

inputs = Helper.inputs()
Helper.preflight!(inputs)

Helper.run!(
  "walks",
  %{
    "resource_contexts" => &Introspection.resource_contexts/1,
    "calls_with_context" => &AshCallScanner.calls_with_context/1,
    "sites" => &AshCallResolver.sites/1
  },
  timing: {1, 3},
  inputs: inputs,
  memory_time: 0.5,
  reduction_time: 0.5,
  before_each: &Helper.cold/1
)
