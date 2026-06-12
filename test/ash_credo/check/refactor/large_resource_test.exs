defmodule AshCredo.Check.Refactor.LargeResourceTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Refactor.LargeResource

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

  test "no issue when resource spans exactly max_lines lines" do
    # defmodule on line 1 through end on line 10 - exactly 10 lines.
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      attributes do
        attribute :field_1, :string
        attribute :field_2, :string
        attribute :field_3, :string
        attribute :field_4, :string
      end
    end
    """

    assert source |> String.trim_trailing("\n") |> String.split("\n") |> length() == 10
    assert [] = run_check(LargeResource, source, max_lines: 10)
  end

  test "reports one anchored issue when resource spans max_lines + 1 lines" do
    # defmodule on line 1 through end on line 11 - exactly 11 lines.
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      attributes do
        attribute :field_1, :string
        attribute :field_2, :string
        attribute :field_3, :string
        attribute :field_4, :string
        attribute :field_5, :string
      end
    end
    """

    assert source |> String.trim_trailing("\n") |> String.split("\n") |> length() == 11
    assert [issue] = run_check(LargeResource, source, max_lines: 10)
    assert issue.message =~ "11 lines"
    assert issue.message =~ "limit: 10"
    assert issue.line_no == 2
    assert issue.trigger == "11 lines"
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
