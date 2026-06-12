defmodule AshCredo.Cache do
  @moduledoc """
  Process-independent key-value cache backed by a single named ETS table
  owned by a supervised GenServer.

  Reads and writes go straight to ETS from the calling process; the
  GenServer exists only to keep the table alive across Credo's transient
  task churn.

  Cleared at the start and end of every Credo run, so each `mix credo`
  invocation sees a fresh table regardless of how long the host VM has
  been alive.

  The OTP application callback starts the cache under supervision when the
  `:ash_credo` application boots. `AshCredo.init/1` additionally calls
  `ensure_started!/0` before any check runs, so the table is also available
  when `mix credo` runs without booting the `:ash_credo` application.

  If the table does not exist - for example when checks are enabled directly
  in `.credo.exs` without registering the `{AshCredo, []}` plugin, so
  `AshCredo.init/1` never runs - every function degrades gracefully instead
  of raising: reads behave as if nothing were cached and writes are no-ops.
  Checks then work correctly, just without cross-call caching. The first
  such access emits a one-time hint to stderr suggesting the plugin
  registration.
  """

  use GenServer

  @table :ash_credo_cache

  @missing_table_hint "ash_credo plugin not registered - checks run uncached; " <>
                        "add `{AshCredo, []}` to `plugins` in .credo.exs"
  @hint_emitted_key {__MODULE__, :missing_table_hint_emitted}

  @doc """
  Starts the cache GenServer. Idempotent - returns the existing pid if
  already started.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Ensures the cache GenServer is running and its ETS table is ready for use.
  Safe to call from any process at any time; idempotent.

  Starts the GenServer directly rather than via `Application.ensure_all_started/1`.
  The latter would cascade through `:ash_credo`'s runtime application deps -
  notably `:credo` - and during `mix credo` the live `Credo.Supervisor` collides
  with that re-start, causing the whole cascade to roll back and the cache to
  fail to start. The OTP application callback skips its cache child when this
  function has already started it.
  """
  @spec ensure_started!() :: :ok
  def ensure_started! do
    case start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> raise "AshCredo.Cache failed to start: #{inspect(reason)}"
    end
  end

  @doc """
  Returns the cached value at `key`, or `default` if absent. Reads bypass
  the GenServer for zero-overhead lookups.
  """
  @spec get(term(), term()) :: term()
  def get(key, default \\ nil) do
    if table_exists?() do
      case :ets.lookup(@table, key) do
        [{^key, value}] -> value
        [] -> default
      end
    else
      warn_missing_table()
      default
    end
  end

  @doc """
  Stores `value` under `key`, overwriting any existing entry. Writes bypass
  the GenServer.
  """
  @spec put(term(), term()) :: :ok
  def put(key, value) do
    if table_exists?() do
      :ets.insert(@table, {key, value})
    else
      warn_missing_table()
    end

    :ok
  end

  @doc """
  Atomically inserts `key` (with a placeholder value) only if absent.
  Returns `true` if this call inserted (the caller is the first to see
  this key), `false` if `key` was already present. Use this when you
  need to act exactly once per key across concurrent callers.

  When the table is missing, returns `true` on every call (nothing is
  ever cached, so every caller looks like the first one).
  """
  @spec insert_new(term()) :: boolean()
  def insert_new(key) do
    if table_exists?() do
      :ets.insert_new(@table, {key, true})
    else
      warn_missing_table()
      true
    end
  end

  @doc "Returns `true` if `key` is present in the cache."
  @spec member?(term()) :: boolean()
  def member?(key) do
    if table_exists?() do
      :ets.member(@table, key)
    else
      warn_missing_table()
      false
    end
  end

  @doc """
  Deletes every entry in the cache. Idempotent and safe to call before
  the cache GenServer has started (no-op in that case).
  """
  @spec clear() :: :ok
  def clear do
    if table_exists?() do
      :ets.delete_all_objects(@table)
    end

    :ok
  end

  @doc """
  Forgets that the missing-table hint was emitted, so the next missing-table
  access emits it again. Test helper that keeps the flag key private to this
  module.
  """
  @spec reset_missing_table_hint() :: :ok
  def reset_missing_table_hint do
    :persistent_term.erase(@hint_emitted_key)
    :ok
  end

  @doc """
  Marks the missing-table hint as already emitted, silencing it for the rest
  of the VM's lifetime. Test helper that keeps the flag key private to this
  module.
  """
  @spec mark_missing_table_hint_emitted() :: :ok
  def mark_missing_table_hint_emitted do
    :persistent_term.put(@hint_emitted_key, true)
  end

  defp table_exists?, do: :ets.whereis(@table) != :undefined

  # One hint per VM, tracked outside the (missing) table: a no-plugin run
  # would otherwise repeat the message once per accessor call per file.
  # Concurrent first callers may rarely both emit; best-effort is fine here.
  defp warn_missing_table do
    if not :persistent_term.get(@hint_emitted_key, false) do
      :persistent_term.put(@hint_emitted_key, true)
      IO.puts(:stderr, @missing_table_hint)
    end
  end

  # ── GenServer callbacks ──

  @impl true
  def init(_opts) do
    table =
      case :ets.whereis(@table) do
        :undefined ->
          :ets.new(@table, [
            :set,
            :public,
            :named_table,
            read_concurrency: true,
            write_concurrency: true
          ])

        existing ->
          existing
      end

    {:ok, table}
  end
end
