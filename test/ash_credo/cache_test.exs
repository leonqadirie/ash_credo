defmodule AshCredo.CacheTest do
  use ExUnit.Case, async: false

  alias AshCredo.Cache

  setup do
    Cache.ensure_started!()
    Cache.clear()
    :ok
  end

  describe "get/2 + put/2" do
    test "returns the put value" do
      Cache.put(:k, 42)
      assert Cache.get(:k) == 42
    end

    test "returns the default when key is absent" do
      assert Cache.get(:missing, :default) == :default
    end

    test "put overwrites" do
      Cache.put(:k, 1)
      Cache.put(:k, 2)
      assert Cache.get(:k) == 2
    end
  end

  describe "insert_new/1" do
    test "returns true on the first insert and false thereafter" do
      assert Cache.insert_new(:once) == true
      assert Cache.insert_new(:once) == false
      assert Cache.insert_new(:once) == false
    end

    test "is atomic across concurrent callers (exactly one wins per key)" do
      key = {:race, make_ref()}
      parent = self()

      tasks =
        for _ <- 1..50 do
          Task.async(fn -> send(parent, {:result, Cache.insert_new(key)}) end)
        end

      Enum.each(tasks, &Task.await/1)

      results =
        for _ <- 1..50 do
          receive do
            {:result, result} -> result
          end
        end

      # Exactly one caller should have inserted; the rest should see false.
      {trues, falses} = Enum.split_with(results, & &1)
      assert length(trues) == 1
      assert length(falses) == 49
    end
  end

  describe "clear/0" do
    test "deletes every entry" do
      Cache.put(:a, 1)
      Cache.put(:b, 2)
      Cache.insert_new(:c)

      Cache.clear()

      assert Cache.get(:a) == nil
      assert Cache.get(:b) == nil
      refute Cache.member?(:c)
    end

    test "is safe to call repeatedly on an empty table" do
      Cache.clear()
      Cache.clear()
      :ok
    end
  end

  describe "ensure_started!/0" do
    test "is idempotent" do
      assert :ok = Cache.ensure_started!()
      assert :ok = Cache.ensure_started!()
    end
  end
end
