defmodule AshCredo.Check.Ash.LargeResourceTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Ash.LargeResource

  test "reports issue when resource exceeds max lines" do
    lines = for i <- 1..20, do: "  attribute :field_#{i}, :string\n"

    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog
    #{Enum.join(lines)}end
    """

    assert [issue] = run_check(LargeResource, source, max_lines: 10)
    assert issue.message =~ "lines"
  end

  test "no issue when under the limit" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog
    end
    """

    assert [] = run_check(LargeResource, source, max_lines: 300)
  end

  test "ignores non-Ash modules" do
    source = """
    defmodule MyApp.Utils do
      def hello, do: :world
    end
    """

    assert [] = run_check(LargeResource, source)
  end
end
