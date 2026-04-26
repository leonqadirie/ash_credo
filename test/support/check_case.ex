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
end
