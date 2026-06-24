defmodule AshCredo.PathFilterPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias AshCredo.PathFilter

  # A single path segment: lowercase letters only, so it never contains a
  # slash or a regex metacharacter and never collides with the "/" delimiter.
  defp segment, do: string(?a..?z, min_length: 1, max_length: 6)

  # A relative filename of 1..5 segments joined by "/".
  defp path, do: segment() |> list_of(min_length: 1, max_length: 5) |> map(&Enum.join(&1, "/"))

  # The mix of entries a real `excluded_paths` config might hold: a bare
  # segment, a segment with a trailing slash, the empty string, or a regex.
  defp entry do
    one_of([
      segment(),
      map(segment(), &(&1 <> "/")),
      constant(""),
      member_of([~r/test/, ~r/\.exs$/])
    ])
  end

  property "excludes a path containing the entry as a full, non-final segment" do
    check all(
            prefix <- list_of(segment(), max_length: 3),
            entry <- segment(),
            suffix <- list_of(segment(), min_length: 1, max_length: 3)
          ) do
      filename = Enum.join(prefix ++ [entry] ++ suffix, "/")
      assert PathFilter.excluded?(filename, [entry])
    end
  end

  property "excludes a filename equal to the entry" do
    check all(entry <- segment()) do
      assert PathFilter.excluded?(entry, [entry])
    end
  end

  property "does not exclude when the entry only appears as a substring of a segment" do
    check all(
            parts <- list_of(segment(), min_length: 1, max_length: 5),
            entry <- segment()
          ) do
      # Each segment strictly contains `entry` but never equals it and is never
      # bracketed by slashes, so segment matching must not fire.
      filename = parts |> Enum.map_join("/", &(&1 <> entry <> "z"))
      refute PathFilter.excluded?(filename, [entry])
    end
  end

  property "a trailing slash on a binary entry does not change the result" do
    check all(filename <- path(), entry <- segment()) do
      assert PathFilter.excluded?(filename, [entry]) ==
               PathFilter.excluded?(filename, [entry <> "/"])
    end
  end

  property "an empty or slash-only entry never excludes anything" do
    check all(filename <- path()) do
      refute PathFilter.excluded?(filename, [""])
      refute PathFilter.excluded?(filename, ["/"])
    end
  end

  property "excluded? holds iff some single entry excludes (any? semantics)" do
    check all(filename <- path(), entries <- list_of(entry(), max_length: 5)) do
      assert PathFilter.excluded?(filename, entries) ==
               Enum.any?(entries, &PathFilter.excluded?(filename, [&1]))
    end
  end

  property "a Regex entry matches exactly when Regex.match? does" do
    regexes = [~r/test/, ~r/^lib/, ~r/\.exs$/, ~r/support/, ~r/[0-9]/]

    check all(filename <- path(), regex <- member_of(regexes)) do
      assert PathFilter.excluded?(filename, [regex]) == Regex.match?(regex, filename)
    end
  end
end
