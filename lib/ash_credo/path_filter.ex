defmodule AshCredo.PathFilter do
  @moduledoc "Shared `excluded_paths` matching used by checks that exempt test directories by default."

  @doc """
  The shared `excluded_paths` default: test directories, where the
  patterns these checks flag are typically intentional. Referenced from
  each check's `param_defaults` so the checks cannot drift apart.
  """
  def default_excluded_paths, do: [~r"/test/", "test"]

  @doc """
  Returns `true` when `filename` matches any entry in `excluded_paths`.

  Entries may be a `Regex` (matched against the full filename) or a binary.
  Binary entries match as path segments: the filename is excluded when it
  equals the entry, starts with `entry <> "/"`, or contains
  `"/" <> entry <> "/"`. That lets `"test"` exclude `test/foo.exs` and
  `/repo/test/foo.exs` without falsely catching `contest/foo.ex`, and lets
  `"priv/seeds.exs"` exclude that exact file.

  Trailing slashes on binary entries are normalised away, so `"test"` and
  `"test/"` behave identically - existing configs that wrote directory
  names with a trailing slash continue to work.
  """
  def excluded?(filename, excluded_paths) do
    Enum.any?(excluded_paths, &matches?(filename, &1))
  end

  defp matches?(filename, %Regex{} = regex), do: Regex.match?(regex, filename)

  defp matches?(filename, path) when is_binary(path) do
    case String.trim_trailing(path, "/") do
      "" ->
        false

      normalized ->
        filename == normalized or
          String.starts_with?(filename, normalized <> "/") or
          String.contains?(filename, "/" <> normalized <> "/")
    end
  end
end
