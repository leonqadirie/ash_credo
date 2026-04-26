defmodule AshCredo.ClearCacheTask do
  @moduledoc false
  # Credo pipeline task appended to `:halt_execution` by `AshCredo.init/1`.
  # Empties the introspection cache after every Credo run so its memory does
  # not linger between invocations in long-lived VMs.
  #
  # `AshCredo.init/1` ALSO clears at the start of every run as a safety net
  # for the case where a previous run crashed before reaching this task.

  use Credo.Execution.Task

  alias AshCredo.Cache

  @impl true
  def call(exec) do
    Cache.clear()
    exec
  end
end
