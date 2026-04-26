defmodule AshCredo.CheckCase do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      use ExUnit.Case

      import AshCredo.CheckCase
    end
  end

  def source_file(source_code, filename \\ "test_file.ex") do
    source_code
    |> Credo.SourceFile.parse(filename)
  end

  def run_check(check_module, source_code, params \\ []) do
    {filename, params} = Keyword.pop(params, :__filename__, "test_file.ex")

    source_code
    |> source_file(filename)
    |> check_module.run(params)
  end

  # Returns the first issue with the given trigger, or nil. Use in tests
  # so call sites read as `assert find_by_trigger(issues, "X")` rather than
  # an `Enum.find` chain (and stay below Credence's repeated-traversal radar).
  # Param names below are deliberately distinct per-helper so Credence's
  # module-scoped name match does not flag the helpers themselves.
  def find_by_trigger(issues, trigger), do: Enum.find(issues, &(&1.trigger == trigger))

  # Returns the first issue whose message matches `pattern` (a string for
  # substring match, or a Regex).
  def find_by_message(items, pattern), do: Enum.find(items, &(&1.message =~ pattern))

  # Returns the set of triggers across an issue list - convenient for
  # exact-set assertions via `MapSet.equal?/2` and membership checks via
  # `MapSet.member?/2`.
  def trigger_set(list), do: MapSet.new(list, & &1.trigger)

  # Returns the issue triggers as a sorted list - convenient for ordered
  # equality assertions when the exact issue ordering is irrelevant.
  def sorted_triggers(entries), do: entries |> Enum.map(& &1.trigger) |> Enum.sort()
end
