defmodule Mix.Tasks.Lint.Credence do
  @shortdoc "Runs Credence semantic checks against lib/ and test/"

  @moduledoc """
  Runs [Credence](https://github.com/Cinderella-Man/credence) on every
  `.ex`/`.exs` file under `lib/` and `test/` and fails if any issues are
  returned.

  Files under any `fixtures/` directory are skipped: they intentionally
  contain code that violates Ash conventions so the plugin's own checks can
  detect them, which would otherwise trip Credence's semantic rules.
  """

  use Mix.Task

  @source_dirs ["lib", "test"]
  @extensions [".ex", ".exs"]
  @excluded_segments ["fixtures"]

  @impl true
  def run(_args) do
    # Credence's semantic phase compiles each file in-process to capture
    # compiler diagnostics. Our test files can't compile standalone here
    # (`:ex_unit` is not started), so each one logs a caught, harmless
    # `[credence_fix] Code.compile_string raised` at :debug. Mute Credence's
    # debug chatter for the run while keeping its :warning-and-up signals.
    Logger.put_application_level(:credence, :warning)

    issues =
      @source_dirs
      |> Enum.flat_map(&source_files/1)
      |> Enum.flat_map(&analyze_file/1)

    if issues == [] do
      Mix.shell().info("Credence: no semantic issues found.")
    else
      Enum.each(issues, &report/1)
      Mix.raise("Credence found #{length(issues)} issue(s).")
    end
  after
    Logger.delete_application_level(:credence)
  end

  defp source_files(dir) do
    if File.dir?(dir) do
      dir
      |> Path.join("**/*")
      |> Path.wildcard()
      |> Enum.filter(fn path -> Path.extname(path) in @extensions end)
      |> Enum.reject(&excluded?/1)
    else
      []
    end
  end

  defp excluded?(path) do
    path
    |> Path.split()
    |> Enum.any?(&(&1 in @excluded_segments))
  end

  defp analyze_file(path) do
    source = File.read!(path)

    case Credence.analyze(source, source: source) do
      %{valid: true} -> []
      %{issues: issues} -> Enum.map(issues, &{path, &1})
    end
  end

  defp report({path, issue}) do
    line = Map.get(issue.meta || %{}, :line, "?")
    Mix.shell().error("#{path}:#{line}: #{issue.rule}: #{issue.message}")
  end
end
