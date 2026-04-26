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

  test "alias to Compiled inside a `for` generator does not leak into a later wrapper-resolving call" do
    # Regression: an alias declared inside a `for` generator is scoped to
    # the construct in Elixir (verified empirically). The walker's default
    # `lexical_scope_nodes: [:with, :for]` enforces that. Without it, the
    # leaked alias would let a later `Compiled.with_compiled_check(...)`
    # call resolve and falsely satisfy the check, producing a false
    # negative. With the default in place, the later call does NOT resolve
    # to Compiled, so the check correctly flags the missing wrapper.
    source = """
    defmodule AshCredo.Check.Warning.LeakedFor do
      def run(source_file, _params) do
        for _ <- (alias AshCredo.Introspection.Compiled; [1]) do
          :ok
        end

        # Outside the `for`, `Compiled` is no longer aliased. Pre-fix, the
        # walker leak made this call look like a real wrapper call.
        Compiled.with_compiled_check(fn -> nil end, fn -> [] end)
      end
    end
    """

    assert [issue] =
             run_check_with_filename(source, "lib/ash_credo/check/warning/leaked_for.ex")

    # The alias was visited inside the for, so compiled_alias_line is set
    # to that line (3). With the fix, has_wrapper_call? stays false, so
    # the issue fires.
    assert issue.line_no == 3
    assert issue.trigger == "AshCredo.Introspection.Compiled"
  end

  test "handles grouped alias syntax" do
    source = """
    defmodule AshCredo.Check.Warning.GroupedAlias do
      alias AshCredo.Introspection.{Compiled, Aliases}

      def run(source_file, _params) do
        Compiled.actions(resource)
      end
    end
    """

    assert [issue] =
             run_check_with_filename(source, "lib/ash_credo/check/warning/grouped_alias.ex")

    assert issue.line_no == 2
    assert issue.trigger == "AshCredo.Introspection.Compiled"
  end
end
