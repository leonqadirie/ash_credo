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
    * `BENCH_COMPARE=1` - report this run next to every other tag's saved
      results for the suite.
    * `BENCH_CHECKS=RaisingCall,Warning.UnknownAction` - restrict
      `bench/checks.exs` to the named checks, by short or `Category.Name`
      form.
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

  @doc """
  The checks `BENCH_CHECKS` names, or `:all` when it is unset. Raises on a
  name that matches no check, so a typo cannot benchmark nothing.
  """
  def selected_checks do
    System.get_env("BENCH_CHECKS", "")
    |> String.split(",", trim: true)
    |> case do
      [] -> :all
      names -> names |> Enum.map(&String.trim/1) |> Enum.map(&find_check!/1) |> Enum.uniq()
    end
  end

  defp find_check!(name) do
    Enum.find(checks(), &(name in [check_name(&1), short_name(&1)])) ||
      raise "BENCH_CHECKS: no check named #{inspect(name)}"
  end

  @doc """
  The check's `Category.Name`, e.g. `"Warning.UnknownAction"`.
  """
  def check_name(check), do: check |> inspect() |> String.replace_prefix("AshCredo.Check.", "")

  def short_name(check), do: check |> Module.split() |> List.last()

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

  @doc """
  `cold!/0` as a Benchee `before_each` hook: passes the input through.
  """
  def cold(source_file) do
    cold!()
    source_file
  end

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
  Raises when no check reports an issue on the smallest input: a broken
  setup (unloaded fixtures, excluded path) would otherwise benchmark checks
  that return `[]` immediately. Then warns for each of the `selected`
  checks that stays silent on every input, since its timing covers only
  the scan.
  """
  def preflight!(inputs, selected \\ []) do
    # Smallest input first, so the guard stays cheap and checks that fire
    # early skip `large`.
    ordered = Enum.sort_by(inputs, fn {_name, sf} -> byte_size(Credo.SourceFile.source(sf)) end)
    {name, smallest} = hd(ordered)
    cold!()

    if run_all(smallest) == [] do
      raise "preflight: no issues on input #{inspect(name)}; the benchmark would measure no-ops"
    end

    for check <- selected, silent?(check, ordered) do
      IO.puts(:stderr, "warning: #{check_name(check)} reports no issues on any input")
    end

    :ok
  end

  defp silent?(check, inputs) do
    Enum.all?(inputs, fn {_name, source_file} ->
      cold!()
      run_check(check, source_file) == []
    end)
  end

  @doc """
  Runs `jobs` and saves the results under the current tag. With
  `BENCH_COMPARE=1`, prints a report of the saved results of every other
  tag next to this run instead of the plain run output.

  `opts` takes Benchee options plus `:timing` (`{warmup, time}` for full
  runs) and `:quick_timing` (for `BENCH_QUICK=1`, default `{0.2, 0.5}`).
  """
  def run!(suite, jobs, opts) do
    tag = tag()
    path = saved_path(suite, tag)
    baselines = if compare?(), do: Path.wildcard(saved_path(suite, "*")) -- [path], else: []

    {warmup, time} =
      if quick?(),
        do: Keyword.get(opts, :quick_timing, {0.2, 0.5}),
        else: Keyword.fetch!(opts, :timing)

    File.mkdir_p!(out_dir())

    # Loading baselines inside `Benchee.run/2` would store them in this
    # run's save file, and Benchee's tag deduplication would then rename or
    # crash on them. The run saves alone; `Benchee.report/1` compares.
    formatters = if baselines == [], do: [], else: [formatters: []]

    base =
      [
        warmup: warmup,
        time: time,
        parallel: 1,
        title: suite,
        save: [path: path, tag: tag],
        print: [configuration: false]
      ] ++ formatters

    Benchee.run(jobs, Keyword.merge(base, Keyword.drop(opts, [:timing, :quick_timing])))

    if baselines != [] do
      Benchee.report(load: baselines ++ [path], title: suite, print: [configuration: false])
    end
  end

  defp compare?, do: System.get_env("BENCH_COMPARE") == "1"

  # Quick runs save apart from full runs, so a comparison never sets short
  # samples against full-length ones.
  defp out_dir, do: if(quick?(), do: Path.join(@out_dir, "quick"), else: @out_dir)

  # `<suite>.<tag>.benchee`: the dot keeps the `checks` wildcard from
  # matching a filtered `checks+<names>` suite's files.
  defp saved_path(suite, tag), do: Path.join(out_dir(), "#{suite}.#{tag}.benchee")

  # Tags become file names: anything outside `[A-Za-z0-9._-]` turns into
  # `-`, so `feat/x` cannot write into a subdirectory.
  defp tag do
    tag =
      case System.get_env("BENCH_TAG") do
        tag when tag not in [nil, ""] -> tag
        _ -> git_ref()
      end

    String.replace(tag, ~r/[^A-Za-z0-9._-]/, "-")
  end

  # A detached HEAD names itself `HEAD`; `git describe` tells checkouts of
  # different tags or commits apart instead.
  defp git_ref do
    case git(["rev-parse", "--abbrev-ref", "HEAD"]) do
      "HEAD" -> git(["describe", "--tags", "--always"])
      branch -> branch
    end
  end

  defp git(args) do
    {out, 0} = System.cmd("git", args)
    String.trim(out)
  end
end

Bench.Helper.boot!()
