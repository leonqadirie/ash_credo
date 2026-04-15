defmodule AshCredo.SelfCheck.EnforceCompiledCheckWrapperTest do
  use AshCredo.CheckCase

  alias AshCredo.SelfCheck.EnforceCompiledCheckWrapper

  defp run_check_with_filename(source, filename) do
    source
    |> source_file(filename)
    |> EnforceCompiledCheckWrapper.run([])
  end

  test "flags check that aliases Compiled without calling with_compiled_check" do
    source = """
    defmodule AshCredo.Check.Warning.BadCheck do
      alias AshCredo.Introspection.Compiled, as: CompiledIntrospection

      def run(source_file, _params) do
        CompiledIntrospection.actions(resource)
      end
    end
    """

    assert [issue] =
             run_check_with_filename(source, "lib/ash_credo/check/warning/bad_check.ex")

    assert issue.line_no == 2
    assert issue.trigger == "AshCredo.Introspection.Compiled"
  end

  test "passes when check aliases Compiled and calls with_compiled_check" do
    source = """
    defmodule AshCredo.Check.Warning.GoodCheck do
      alias AshCredo.Introspection.Compiled, as: CompiledIntrospection

      def run(source_file, params) do
        CompiledIntrospection.with_compiled_check(
          fn -> format_issue(params) end,
          fn -> [] end
        )
      end
    end
    """

    assert [] =
             run_check_with_filename(source, "lib/ash_credo/check/warning/good_check.ex")
  end

  test "does not treat unrelated with_compiled_check calls as success" do
    source = """
    defmodule AshCredo.Check.Warning.BadCheck do
      alias AshCredo.Introspection.Compiled

      def run(source_file, _params) do
        Compiled.actions(resource)

        Example.Other.with_compiled_check(
          fn -> :ok end,
          fn -> [] end
        )
      end
    end
    """

    assert [issue] =
             run_check_with_filename(source, "lib/ash_credo/check/warning/bad_check.ex")

    assert issue.line_no == 2
    assert issue.trigger == "AshCredo.Introspection.Compiled"
  end

  test "passes when check does not alias Compiled at all" do
    source = """
    defmodule AshCredo.Check.Warning.AstOnlyCheck do
      alias AshCredo.Introspection

      def run(source_file, _params) do
        Introspection.resource_modules(source_file)
      end
    end
    """

    assert [] =
             run_check_with_filename(source, "lib/ash_credo/check/warning/ast_only_check.ex")
  end

  test "ignores files outside the check directory" do
    source = """
    defmodule AshCredo.SomeHelper do
      alias AshCredo.Introspection.Compiled, as: CompiledIntrospection

      def helper(resource) do
        CompiledIntrospection.actions(resource)
      end
    end
    """

    assert [] = run_check_with_filename(source, "lib/ash_credo/some_helper.ex")
  end

  test "matches check files by the trailing lib/ash_credo/check path" do
    source = """
    defmodule AshCredo.Check.Warning.BadCheck do
      alias AshCredo.Introspection.Compiled, as: CompiledIntrospection

      def run(source_file, _params) do
        CompiledIntrospection.actions(resource)
      end
    end
    """

    assert [issue] =
             run_check_with_filename(
               source,
               "/tmp/lib/ash_credo/lib/ash_credo/check/warning/bad_check.ex"
             )

    assert issue.line_no == 2
    assert issue.trigger == "AshCredo.Introspection.Compiled"
  end

  test "handles bare alias without as:" do
    source = """
    defmodule AshCredo.Check.Design.BareAlias do
      alias AshCredo.Introspection.Compiled

      def run(source_file, _params) do
        Compiled.actions(resource)
      end
    end
    """

    assert [issue] =
             run_check_with_filename(source, "lib/ash_credo/check/design/bare_alias.ex")

    assert issue.line_no == 2
  end
end
