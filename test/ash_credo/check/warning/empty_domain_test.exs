defmodule AshCredo.Check.Warning.EmptyDomainTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Warning.EmptyDomain

  test "reports issue for domain with no resources section" do
    source = """
    defmodule MyApp.Blog do
      use Ash.Domain
    end
    """

    assert [issue] = run_check(EmptyDomain, source)
    assert issue.message =~ "no `resources` block"
    assert issue.line_no == 2
  end

  test "reports issue for domain with empty resources section" do
    source = """
    defmodule MyApp.Blog do
      use Ash.Domain

      resources do
      end
    end
    """

    assert [issue] = run_check(EmptyDomain, source)
    assert issue.message =~ "empty"
  end

  test "no issue when resources are registered" do
    source = """
    defmodule MyApp.Blog do
      use Ash.Domain

      resources do
        resource MyApp.Post
      end
    end
    """

    assert [] = run_check(EmptyDomain, source)
  end

  test "ignores non-Domain modules" do
    source = """
    defmodule MyApp.Utils do
      def hello, do: :world
    end
    """

    assert [] = run_check(EmptyDomain, source)
  end
end
