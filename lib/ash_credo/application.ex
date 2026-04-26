defmodule AshCredo.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Skip the cache child if `AshCredo.Cache.ensure_started!/0` already
    # started it directly (e.g. plugin init under `mix credo` in a host
    # project). Without this the supervisor would fail with
    # `{:already_started, pid}`.
    children =
      case Process.whereis(AshCredo.Cache) do
        nil -> [AshCredo.Cache]
        _pid -> []
      end

    opts = [strategy: :one_for_one, name: AshCredo.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
