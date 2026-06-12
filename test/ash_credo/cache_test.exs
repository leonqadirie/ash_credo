defmodule AshCredo.CacheTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias AshCredo.Cache

  @table :ash_credo_cache

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
      # The receive loop above guarantees 50 results, so |falses| = 49 follows
      # from |trues| = 1.
      {trues, _falses} = Enum.split_with(results, & &1)
      assert [_] = trues
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

  describe "when the ETS table is missing" do
    # Simulates running checks without the plugin registered in .credo.exs:
    # `AshCredo.init/1` never runs, so the table is never created. Accessors
    # must degrade to "nothing cached" defaults instead of raising.
    setup do
      stop_cache_owner()
      # Pretend the hint was already emitted so the accessor tests below
      # stay silent; the hint test resets this to exercise the first call.
      Cache.mark_missing_table_hint_emitted()

      on_exit(fn ->
        Cache.reset_missing_table_hint()
        restart_cache_owner()
      end)

      :ok
    end

    test "get/2 returns the default" do
      assert Cache.get(:anything) == nil
      assert Cache.get(:anything, :default) == :default
    end

    test "put/2 is a no-op that returns :ok" do
      assert Cache.put(:k, 1) == :ok
      # Still no table, and nothing was stored anywhere.
      assert :ets.whereis(@table) == :undefined
    end

    test "insert_new/1 returns true (nothing is ever cached)" do
      assert Cache.insert_new(:once) == true
      assert Cache.insert_new(:once) == true
    end

    test "member?/1 returns false" do
      refute Cache.member?(:k)
    end

    test "the first access emits a one-time stderr hint suggesting plugin registration" do
      Cache.reset_missing_table_hint()

      hint = capture_io(:stderr, fn -> Cache.get(:k) end)
      assert hint =~ "ash_credo plugin not registered"
      assert hint =~ "add `{AshCredo, []}` to `plugins`"

      # Every subsequent accessor call stays silent.
      assert capture_io(:stderr, fn ->
               Cache.get(:k)
               Cache.put(:k, 1)
               Cache.insert_new(:k)
               Cache.member?(:k)
             end) == ""
    end
  end

  describe "missing-table hint with the table present" do
    test "accessors never emit the hint" do
      Cache.reset_missing_table_hint()

      assert capture_io(:stderr, fn ->
               Cache.put(:k, 1)
               Cache.get(:k)
               Cache.insert_new(:other)
               Cache.member?(:k)
             end) == ""
    end
  end

  defp stop_cache_owner do
    case Process.whereis(Cache) do
      nil ->
        :ok

      pid ->
        # Detach from the application supervisor (if supervised) so the
        # child is not immediately restarted, then stop the owner.
        if sup = Process.whereis(AshCredo.Supervisor) do
          _ = Supervisor.terminate_child(sup, Cache)
          _ = Supervisor.delete_child(sup, Cache)
        end

        if Process.alive?(pid) do
          ref = Process.monitor(pid)
          GenServer.stop(pid)

          receive do
            {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
          after
            1_000 -> raise "cache owner did not stop"
          end
        end
    end

    wait_until(fn -> :ets.whereis(@table) == :undefined end)
  end

  defp restart_cache_owner do
    # Restart under the application supervisor (not via ensure_started!/0,
    # which would link the GenServer to this short-lived on_exit process
    # and take the cache down with it).
    case Process.whereis(AshCredo.Supervisor) do
      nil ->
        Cache.ensure_started!()

      sup ->
        case Supervisor.start_child(sup, Cache) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, :already_present} -> {:ok, _pid} = Supervisor.restart_child(sup, Cache)
        end
    end

    wait_until(fn -> :ets.whereis(@table) != :undefined end)
  end

  defp wait_until(fun, attempts \\ 200) do
    cond do
      fun.() -> :ok
      attempts == 0 -> raise "condition not met in time"
      true -> wait_until(fun, attempts - 1)
    end
  end
end
