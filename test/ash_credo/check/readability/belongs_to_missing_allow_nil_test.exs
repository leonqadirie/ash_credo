defmodule AshCredo.Check.Readability.BelongsToMissingAllowNilTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Readability.BelongsToMissingAllowNil

  test "reports issue for belongs_to without allow_nil?" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      relationships do
        belongs_to :author, MyApp.Author
      end
    end
    """

    assert [issue] = run_check(BelongsToMissingAllowNil, source)
    assert issue.message =~ "allow_nil?"
    assert issue.message =~ ":author"
  end

  test "no issue when allow_nil? is explicit" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      relationships do
        belongs_to :author, MyApp.Author, allow_nil?: false
      end
    end
    """

    assert [] = run_check(BelongsToMissingAllowNil, source)
  end

  test "no issue when allow_nil? is declared inside the relationship block" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      relationships do
        belongs_to :author, MyApp.Author do
          allow_nil? false
        end
      end
    end
    """

    assert [] = run_check(BelongsToMissingAllowNil, source)
  end

  test "ignores has_many and has_one" do
    source = """
    defmodule MyApp.Author do
      use Ash.Resource, domain: MyApp.Blog

      relationships do
        has_many :posts, MyApp.Post
        has_one :profile, MyApp.Profile
      end
    end
    """

    assert [] = run_check(BelongsToMissingAllowNil, source)
  end

  test "no issue when no relationships section" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog
    end
    """

    assert [] = run_check(BelongsToMissingAllowNil, source)
  end

  test "ignores non-Ash modules" do
    source = """
    defmodule MyApp.Utils do
      def hello, do: :world
    end
    """

    assert [] = run_check(BelongsToMissingAllowNil, source)
  end
end
