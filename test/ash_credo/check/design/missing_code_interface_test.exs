defmodule AshCredo.Check.Design.MissingCodeInterfaceTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Design.MissingCodeInterface

  test "reports issue when actions exist but no code_interface" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        defaults [:read]
      end
    end
    """

    assert [issue] = run_check(MissingCodeInterface, source)
    assert issue.message =~ "code_interface"
  end

  test "no issue when code_interface exists" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        defaults [:read]
      end

      code_interface do
        define :read
      end
    end
    """

    assert [] = run_check(MissingCodeInterface, source)
  end

  test "no issue when no actions section" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog
    end
    """

    assert [] = run_check(MissingCodeInterface, source)
  end

  test "no issue when actions section has only config but no actual actions" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        default_accept :*
      end
    end
    """

    assert [] = run_check(MissingCodeInterface, source)
  end

  test "ignores non-Ash modules" do
    source = """
    defmodule MyApp.Utils do
      def hello, do: :world
    end
    """

    assert [] = run_check(MissingCodeInterface, source)
  end
end
