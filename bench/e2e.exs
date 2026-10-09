# A full `Credo.run` with the AshCredo plugin over a corpus of every input
# written to disk. Covers plugin init, cache lifecycle, and Credo's
# parallel check workers. Memory and reductions stay off: Credo runs checks
# in Task processes, and Benchee measures only the calling process.
#
#     MIX_ENV=test mix run bench/e2e.exs

alias Bench.Helper
alias Credo.CLI.Output.Shell

Code.require_file("support/bench_helper.exs", __DIR__)

corpus = Path.expand("../tmp/bench/corpus", __DIR__)
File.rm_rf!(corpus)
File.mkdir_p!(Path.join(corpus, "lib"))

Enum.each(Helper.sources(), fn {name, code} ->
  File.write!(Path.join([corpus, "lib", "#{name}.ex"]), code)
end)

# Runs every AshCredo check through the plugin and nothing else, so Credo's
# built-in checks don't dilute the measurement.
config = %{
  configs: [
    %{
      name: "default",
      files: %{included: ["lib/"], excluded: []},
      plugins: [{AshCredo, []}],
      strict: true,
      checks: %{enabled: Enum.map(Helper.checks(), &{&1, []})}
    }
  ]
}

config_file = Path.join(corpus, ".credo.exs")
File.write!(config_file, inspect(config, limit: :infinity, pretty: true))

args = [
  "--config-file",
  config_file,
  "--working-dir",
  corpus,
  "--mute-exit-status",
  "--format",
  "oneline"
]

# `Shell.suppress_output/1` returns the shell's reply, not the callback's
# value, so the Execution struct travels back by message.
credo_run = fn ->
  parent = self()
  Shell.suppress_output(fn -> send(parent, {:credo_exec, Credo.run(args)}) end)

  receive do
    {:credo_exec, exec} -> exec
  end
end

# Credo keeps per-run state in global services; repeated runs in one VM
# must report the same issues or the timings compare different work.
issue_counts =
  for _ <- 1..3, do: credo_run.() |> Credo.Execution.get_issues() |> length()

case Enum.uniq(issue_counts) do
  [count] when count > 0 -> IO.puts("e2e preflight: #{count} issues per run")
  counts -> raise "e2e preflight: unstable or empty issue counts #{inspect(counts)}"
end

Benchee.run(
  %{"credo_run" => credo_run},
  Helper.run_opts("e2e", timing: {1, if(Helper.quick?(), do: 5, else: 15)})
)
