defmodule Mix.Tasks.Lint.Credence do
  @shortdoc "Runs Credence semantic checks against lib/"

  @moduledoc """
  Runs [Credence](https://github.com/Cinderella-Man/credence) on every
  `.ex`/`.exs` file under `lib/` and fails if any issues are returned.

  `test/support/fixtures` deliberately contains anti-patterns for AshCredo's
  own checks to detect, so it is not analysed.
  """

  use Mix.Task

  @source_dirs ["lib"]
  @extensions [".ex", ".exs"]

  @impl true
  def run(_args) do
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
  end

  defp source_files(dir) do
    if File.dir?(dir) do
      dir
      |> Path.join("**/*")
      |> Path.wildcard()
      |> Enum.filter(fn path -> Path.extname(path) in @extensions end)
    else
      []
    end
  end

  defp analyze_file(path) do
    case Credence.analyze(File.read!(path)) do
      %{valid: true} -> []
      %{issues: issues} -> Enum.map(issues, &{path, &1})
    end
  end

  defp report({path, issue}) do
    line = Map.get(issue.meta || %{}, :line, "?")
    Mix.shell().error("#{path}:#{line}: [#{issue.severity}] #{issue.rule}: #{issue.message}")
  end
end
