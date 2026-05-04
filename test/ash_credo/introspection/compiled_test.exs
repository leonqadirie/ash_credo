defmodule AshCredo.Introspection.CompiledTest do
  use ExUnit.Case, async: false

  alias AshCredo.Cache
  alias AshCredo.Introspection.Compiled

  setup do
    Cache.ensure_started!()
    Compiled.clear_cache()
    :ok
  end

  describe "enclosing_domain/1" do
    test "memoizes the resolved domain so repeat calls hit the cache" do
      module = AshCredoFixtures.Blog.Changes.Archive
      cache_key = {{Compiled, :enclosing_domain}, module}

      refute Cache.member?(cache_key)

      first = Compiled.enclosing_domain(module)
      assert first == AshCredoFixtures.Blog
      assert Cache.member?(cache_key)

      second = Compiled.enclosing_domain(module)
      assert second == first
    end

    test "memoizes nil results for modules with no enclosing domain" do
      module = AshCredoFixtures.Plain
      cache_key = {{Compiled, :enclosing_domain}, module}

      refute Cache.member?(cache_key)
      assert Compiled.enclosing_domain(module) == nil
      assert Cache.member?(cache_key)
      assert Compiled.enclosing_domain(module) == nil
    end
  end
end
