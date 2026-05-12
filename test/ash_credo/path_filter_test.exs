defmodule AshCredo.PathFilterTest do
  use ExUnit.Case, async: true

  alias AshCredo.PathFilter

  describe "binary entries" do
    test "matches the exact filename" do
      assert PathFilter.excluded?("priv/seeds.exs", ["priv/seeds.exs"])
    end

    test "matches when the filename starts with the entry as a path segment" do
      assert PathFilter.excluded?("test/foo.exs", ["test"])
      assert PathFilter.excluded?("test/support/factories.ex", ["test"])
    end

    test "matches when the entry appears as a path segment anywhere in the filename" do
      assert PathFilter.excluded?("/Users/dev/proj/test/foo_test.exs", ["test"])
    end

    test "does not match a substring that isn't a full path segment" do
      refute PathFilter.excluded?("contest/foo.ex", ["test"])
      refute PathFilter.excluded?("attest_helpers.ex", ["test"])
    end

    test "returns false for an empty excluded_paths list" do
      refute PathFilter.excluded?("test/foo.exs", [])
    end
  end

  describe "trailing slash on binary entries" do
    # Before normalisation, `"test/"` matched against `"test/foo.exs"` would
    # ask whether the filename started with `"test//"` - never true. This
    # regression silently disabled excluded_paths configs that wrote
    # directory names with a trailing slash, even though the docs read as
    # if either spelling worked.

    test "is equivalent to the unsuffixed form for prefix matches" do
      assert PathFilter.excluded?("test/foo.exs", ["test/"])
      assert PathFilter.excluded?("test/support/factories.ex", ["test/"])
    end

    test "is equivalent to the unsuffixed form for embedded segment matches" do
      assert PathFilter.excluded?("/Users/dev/proj/test/foo_test.exs", ["test/"])
    end

    test "still rejects substring-only matches" do
      refute PathFilter.excluded?("contest/foo.ex", ["test/"])
    end

    test "treats `\"/\"` as a no-op rather than matching every absolute path" do
      # `String.trim_trailing("/", "/")` is `""`. Without the empty-string
      # guard, the prefix check would degenerate into `starts_with?(filename, "/")`
      # and silently exclude every absolute path - a far worse failure than
      # the original "trailing-slash entries do nothing" behaviour.
      refute PathFilter.excluded?("/Users/dev/proj/lib/foo.ex", ["/"])
    end
  end

  describe "regex entries" do
    test "matches against the full filename" do
      # `~r"/test/"` matches the literal `/test/` substring, so it hits
      # absolute paths and embedded test segments but NOT a filename that
      # starts with `test/`. The default `excluded_paths` pairs this regex
      # with the binary `"test"` to cover both shapes.
      assert PathFilter.excluded?("/repo/test/foo.exs", [~r"/test/"])
      assert PathFilter.excluded?("apps/web/test/foo.exs", [~r"/test/"])
    end

    test "does not match when the regex does not apply" do
      refute PathFilter.excluded?("lib/foo.ex", [~r"/test/"])
      refute PathFilter.excluded?("test/foo.exs", [~r"/test/"])
    end
  end

  describe "mixed entries" do
    test "matches when any entry matches" do
      assert PathFilter.excluded?("priv/seeds.exs", [~r"/test/", "priv"])
      assert PathFilter.excluded?("test/foo.exs", [~r"/test/", "test"])
    end

    test "returns false when no entry matches" do
      refute PathFilter.excluded?("lib/foo.ex", [~r"/test/", "priv"])
    end
  end
end
