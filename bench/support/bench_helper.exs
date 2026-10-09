Code.require_file("synthetic.exs", __DIR__)

defmodule Bench.Helper do
  @moduledoc """
  Shared setup for the `bench/*.exs` suites.

  Run each suite with `MIX_ENV=test mix run bench/<suite>.exs`: the test env
  compiles the `AshCredoFixtures` modules that compiled checks introspect.

  Environment variables:

    * `BENCH_QUICK=1` - short warmup/time and only the `fixtures` and
      `medium` inputs.
    * `BENCH_TAG` - label for saved results; defaults to the git branch.
    * `BENCH_COMPARE=1` - load every other tag's saved results for the
      suite and print the comparison.
  """

  alias Bench.Synthetic

  @fixture_path "test/support/fixtures/ash_fixtures.ex"
  @out_dir "tmp/bench"

  @doc """
  Every check module, discovered from the check files on disk the same way
  test/ash_credo_test.exs does. `boot!/0` stores the list once so the timed
  jobs don't glob the filesystem.
  """
  def checks, do: :persistent_term.get({__MODULE__, :checks})

  defp load_checks! do
    checks = AshCredo.CheckRegistry.check_modules()
    missing = Enum.reject(checks, &Code.ensure_loaded?/1)

    if missing != [] do
      raise "check files without a loadable module: #{inspect(missing)}"
    end

    checks
  end

  # `mix run` skips `:credo` because the dep is `runtime: false`, so start
  # it the same way test/test_helper.exs does.
  def boot! do
    {:ok, _} = Application.ensure_all_started(:logger)
    Credo.Application.start(nil, nil)
    AshCredo.Cache.ensure_started!()
    :persistent_term.put({__MODULE__, :checks}, load_checks!())
  end

  def quick?, do: System.get_env("BENCH_QUICK") == "1"

  # Clears both the AST-walk memo and the compiled-introspection memo; they
  # share one ETS table.
  def cold!, do: AshCredo.Cache.clear()

  def run_check(check, source_file), do: check.run(source_file, [])

  def run_all(source_file), do: Enum.flat_map(checks(), &run_check(&1, source_file))

  @doc """
  Raw sources keyed by input name. Quick mode keeps `fixtures` and `medium`.
  """
  def sources do
    all =
      [{"fixtures", File.read!(@fixture_path)}] ++
        Enum.map(Synthetic.sizes(), &{Atom.to_string(&1), Synthetic.source(&1)})

    if quick?(), do: Enum.filter(all, &(elem(&1, 0) in ["fixtures", "medium"])), else: all
  end

  @doc """
  Parsed `Credo.SourceFile`s keyed by input name, restricted to `only` when
  given. Filenames sit under `lib/bench/`: a `test/` path would trip the
  default `excluded_paths` and silently disable seven checks.
  """
  def inputs(only \\ nil) do
    sources()
    |> Enum.filter(fn {name, _} -> only == nil or name in only end)
    |> Map.new(fn {name, code} -> {name, parse!(code, "lib/bench/#{name}.ex")} end)
  end

  defp parse!(code, filename) do
    source_file = Credo.SourceFile.parse(code, filename)

    if source_file.status != :valid do
      raise "bench source failed to parse: #{filename}"
    end

    source_file
  end

  @doc """
  Runs every check once per input and raises if any input yields no issues.
  A no-op setup (unloaded fixtures, excluded path) would otherwise benchmark
  checks that return `[]` immediately.
  """
  def preflight!(inputs) do
    Enum.each(inputs, fn {name, source_file} ->
      cold!()

      if run_all(source_file) == [] do
        raise "preflight: no issues on input #{inspect(name)}; the benchmark would measure no-ops"
      end
    end)
  end

  @doc """
  Benchee options shared by every suite: timing, quick mode, save under the
  current tag, and optional load of other tags for comparison.
  """
  def run_opts(suite, opts) do
    tag = tag()
    {warmup, time} = if quick?(), do: {0.2, 0.5}, else: Keyword.fetch!(opts, :timing)
    File.mkdir_p!(@out_dir)

    base = [
      warmup: warmup,
      time: time,
      parallel: 1,
      title: suite,
      save: [path: saved_path(suite, tag), tag: tag],
      print: [configuration: false]
    ]

    base
    |> Keyword.merge(Keyword.delete(opts, :timing))
    |> maybe_load(suite, tag)
  end

  defp maybe_load(opts, suite, tag) do
    paths = Path.wildcard(Path.join(@out_dir, "#{suite}-*.benchee")) -- [saved_path(suite, tag)]

    if System.get_env("BENCH_COMPARE") == "1" and paths != [] do
      Keyword.put(opts, :load, paths)
    else
      opts
    end
  end

  defp saved_path(suite, tag), do: Path.join(@out_dir, "#{suite}-#{tag}.benchee")

  defp tag do
    case System.get_env("BENCH_TAG") do
      tag when tag not in [nil, ""] ->
        tag

      _ ->
        {branch, 0} = System.cmd("git", ["rev-parse", "--abbrev-ref", "HEAD"])
        branch |> String.trim() |> String.replace("/", "-")
    end
  end
end

Bench.Helper.boot!()
