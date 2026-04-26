defmodule AshCredo.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [AshCredo.Introspection.Cache]
    opts = [strategy: :one_for_one, name: AshCredo.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
