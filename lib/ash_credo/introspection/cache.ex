defmodule AshCredo.Introspection.Cache do
  @moduledoc """
  Process-independent cache for compiled-introspection results.

  Backed by a single named ETS table owned by a supervised GenServer.
  Reads and writes go straight to ETS from the calling process; the
  GenServer exists only to keep the table alive across Credo's transient
  task churn.

  Cleared at the start of every Credo run by `AshCredo.init/1`, so each
  `mix credo` invocation sees a fresh table regardless of how long the
  host VM has been alive.

  Started by `AshCredo.Application` (see `mix.exs` `:mod`).
  `AshCredo.init/1` additionally calls `ensure_started!/0` before any
  check runs, so the table is also available when `mix credo` runs
  without booting the `:ash_credo` application.
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
  Ensures the cache GenServer is running and its ETS table is ready for
  use. Safe to call from any process at any time. Raises if startup fails
  for a reason other than "already started."

  Blocks via a `:ready` GenServer call after start so that a concurrent
  caller racing with another caller's `init/1` cannot proceed before the
  ETS table exists. (`GenServer.start_link/3` returning `{:error,
  {:already_started, pid}}` only proves the GenServer is registered, not
  that its `init/1` has finished.)
  """
  @spec ensure_started!() :: :ok
  def ensure_started! do
    pid =
      case start_link() do
        {:ok, pid} ->
          pid

        {:error, {:already_started, pid}} ->
          pid

        {:error, reason} ->
          raise "AshCredo.Introspection.Cache failed to start: #{inspect(reason)}"
      end

    :ok = GenServer.call(pid, :ready)
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

  # Readiness probe used by `ensure_started!/0`. GenServer message handling
  # is serialized after `init/1`, so a `:ready` call cannot return until
  # the table exists.
  @impl true
  def handle_call(:ready, _from, table), do: {:reply, :ok, table}
end
