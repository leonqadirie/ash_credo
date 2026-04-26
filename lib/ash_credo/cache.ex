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
  """

  use GenServer

  @table :ash_credo_cache

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
    case :ets.lookup(@table, key) do
      [{^key, value}] -> value
      [] -> default
    end
  end

  @doc """
  Stores `value` under `key`, overwriting any existing entry. Writes bypass
  the GenServer.
  """
  @spec put(term(), term()) :: :ok
  def put(key, value) do
    :ets.insert(@table, {key, value})
    :ok
  end

  @doc """
  Atomically inserts `key` (with a placeholder value) only if absent.
  Returns `true` if this call inserted (the caller is the first to see
  this key), `false` if `key` was already present. Use this when you
  need to act exactly once per key across concurrent callers.
  """
  @spec insert_new(term()) :: boolean()
  def insert_new(key) do
    :ets.insert_new(@table, {key, true})
  end

  @doc "Returns `true` if `key` is present in the cache."
  @spec member?(term()) :: boolean()
  def member?(key), do: :ets.member(@table, key)

  @doc """
  Deletes every entry in the cache. Idempotent and safe to call before
  the cache GenServer has started (no-op in that case).
  """
  @spec clear() :: :ok
  def clear do
    if :ets.whereis(@table) != :undefined do
      :ets.delete_all_objects(@table)
    end

    :ok
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
