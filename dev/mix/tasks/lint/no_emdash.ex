defmodule Mix.Tasks.Lint.NoEmdash do
  @shortdoc "Checks for em dashes in source files"

  @moduledoc "Fails if any source file contains an em dash. Use a hyphen (-) instead."

  use Mix.Task

  # U+2014 EM DASH
  @em_dash <<0xE2, 0x80, 0x94>>
  @source_dirs ["dev", "lib", "test", "config"]
  @source_files ["README.md"]
  @extensions [".ex", ".exs", ".md"]

  @impl true
  def run(_args) do
    dir_files = Enum.flat_map(@source_dirs, &source_files/1)
    standalone = Enum.filter(@source_files, &File.exists?/1)

    hits =
      (dir_files ++ standalone)
      |> Enum.flat_map(&check_file/1)

    if hits == [] do
      Mix.shell().info("No em dashes found.")
    else
      Enum.each(hits, fn {file, line_no, line} ->
        Mix.shell().error("#{file}:#{line_no}: #{String.trim(line)}")
      end)

      Mix.raise("Found em dashes in #{length(hits)} location(s). Use hyphens (-) instead.")
    end
  end

  defp source_files(dir) do
    if File.dir?(dir) do
      Path.wildcard(Path.join(dir, "**/*"))
      |> Enum.filter(fn path -> Path.extname(path) in @extensions end)
    else
      []
    end
  end

  defp check_file(path) do
    path
    |> File.stream!()
    |> Stream.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if String.contains?(line, @em_dash), do: [{path, line_no, line}], else: []
    end)
  end
end
