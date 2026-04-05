defmodule AshCredo.Check.Warning.MissingDomainTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Warning.MissingDomain

  test "reports issue when domain is missing" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource
    end
    """

    assert [issue] = run_check(MissingDomain, source)
    assert issue.message =~ "domain:"
  end

  test "no issue when domain is present" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog
    end
    """

    assert [] = run_check(MissingDomain, source)
  end

  test "ignores embedded resources without a domain" do
    source = """
    defmodule MyApp.Post.Metadata do
      use Ash.Resource, data_layer: :embedded
    end
    """

    assert [] = run_check(MissingDomain, source)
  end

  test "checks each resource module independently" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog
    end

    defmodule MyApp.Comment do
      use Ash.Resource
    end
    """

    assert [issue] = run_check(MissingDomain, source)
    assert issue.message =~ "domain:"
    assert issue.line_no == 6
  end

  test "ignores non-Ash modules" do
    source = """
    defmodule MyApp.Utils do
      def hello, do: :world
    end
    """

    assert [] = run_check(MissingDomain, source)
  end
end
