defmodule AshCredo.SelfCheck.EnforceCompiledIntrospectionBoundaryTest do
  use AshCredo.CheckCase

  alias AshCredo.SelfCheck.EnforceCompiledIntrospectionBoundary

  defp run_check_with_filename(source, filename) do
    source
    |> source_file(filename)
    |> EnforceCompiledIntrospectionBoundary.run([])
  end

  test "flags banned module calls through a top-level alias" do
    source = """
    defmodule MyCheck do
      alias Ash.Resource.Info, as: Info

      def run(resource) do
        Info.actions(resource)
      end
    end
    """

    assert [issue] = run_check(EnforceCompiledIntrospectionBoundary, source)
    assert issue.line_no == 5
    assert issue.trigger == "Ash.Resource.Info.actions"
  end

  test "flags banned module calls through a function-local alias" do
    source = """
    defmodule MyCheck do
      def run(resource) do
        alias Ash.Resource.Info, as: Info
        Info.actions(resource)
      end
    end
    """

    assert [issue] = run_check(EnforceCompiledIntrospectionBoundary, source)
    assert issue.line_no == 4
    assert issue.trigger == "Ash.Resource.Info.actions"
  end

  test "does not use aliases declared after the call site" do
    source = """
    defmodule MyCheck do
      def run(resource) do
        Info.actions(resource)
        alias Ash.Resource.Info, as: Info
      end
    end
    """

    assert [] = run_check(EnforceCompiledIntrospectionBoundary, source)
  end

  test "does not exempt similarly named files outside the gateway path" do
    source = """
    defmodule MyCheck do
      def run(resource) do
        Ash.Resource.Info.actions(resource)
      end
    end
    """

    assert [issue] =
             run_check_with_filename(source, "lib/ash_credo/foo_introspection/compiled.ex")

    assert issue.line_no == 3
    assert issue.trigger == "Ash.Resource.Info.actions"
  end

  test "exempts the compiled introspection gateway file itself" do
    source = """
    defmodule AshCredo.Introspection.Compiled do
      def actions(resource) do
        Ash.Resource.Info.actions(resource)
      end
    end
    """

    assert [] =
             run_check_with_filename(source, "lib/ash_credo/introspection/compiled.ex")
  end
end
