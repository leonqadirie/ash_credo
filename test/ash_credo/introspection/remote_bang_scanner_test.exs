defmodule AshCredo.Introspection.RemoteBangScannerTest do
  use AshCredo.CheckCase

  alias AshCredo.Introspection.RemoteBangScanner

  test "resolves implementation calls and computed module names in their respective contexts" do
    source = """
    defmodule MyApp.Outer do
      defimpl Inspect, for: Foo do
        def go, do: __MODULE__.Api.run!()
      end
      defmodule Module.concat([__MODULE__.Api.name!()]) do
        :ok
      end
    end
    """

    assert [{_, [:Inspect, :Foo, :Api], :run!}, {_, [:MyApp, :Outer, :Api], :name!}] =
             RemoteBangScanner.calls(source_file(source))
  end
end
