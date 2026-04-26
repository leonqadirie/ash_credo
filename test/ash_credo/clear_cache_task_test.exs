defmodule AshCredo.ClearCacheTaskTest do
  use ExUnit.Case, async: false

  alias AshCredo.Cache
  alias AshCredo.ClearCacheTask

  setup do
    Cache.ensure_started!()
    Cache.clear()
    :ok
  end

  test "clears every cache entry and returns the exec struct" do
    Cache.put(:a, 1)
    Cache.put(:b, 2)
    Cache.insert_new(:c)

    exec = %Credo.Execution{}

    assert ^exec = ClearCacheTask.call(exec)

    assert Cache.get(:a) == nil
    assert Cache.get(:b) == nil
    refute Cache.member?(:c)
  end

  test "is safe to call when the cache is already empty" do
    exec = %Credo.Execution{}
    assert ^exec = ClearCacheTask.call(exec)
    assert ^exec = ClearCacheTask.call(exec)
  end
end
