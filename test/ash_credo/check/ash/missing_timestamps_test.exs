defmodule AshCredo.Check.Ash.MissingTimestampsTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Ash.MissingTimestamps

  test "reports issue when timestamps missing" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, data_layer: AshPostgres.DataLayer

      attributes do
        uuid_primary_key :id
        attribute :title, :string
      end
    end
    """

    assert [issue] = run_check(MissingTimestamps, source)
    assert issue.message =~ "missing timestamps"
  end

  test "no issue with timestamps()" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, data_layer: AshPostgres.DataLayer

      attributes do
        uuid_primary_key :id
        attribute :title, :string
        timestamps()
      end
    end
    """

    assert [] = run_check(MissingTimestamps, source)
  end

  test "no issue with create_timestamp + update_timestamp" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, data_layer: AshPostgres.DataLayer

      attributes do
        uuid_primary_key :id
        attribute :title, :string
        create_timestamp :inserted_at
        update_timestamp :updated_at
      end
    end
    """

    assert [] = run_check(MissingTimestamps, source)
  end

  test "reports issue with only create_timestamp (no update)" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, data_layer: AshPostgres.DataLayer

      attributes do
        uuid_primary_key :id
        create_timestamp :inserted_at
      end
    end
    """

    assert [_issue] = run_check(MissingTimestamps, source)
  end

  test "ignores resources without a data layer" do
    source = """
    defmodule MyApp.Embedded do
      use Ash.Resource, domain: MyApp.Blog

      attributes do
        attribute :name, :string
      end
    end
    """

    assert [] = run_check(MissingTimestamps, source)
  end

  test "ignores embedded resources" do
    source = """
    defmodule MyApp.Embedded do
      use Ash.Resource, data_layer: :embedded

      attributes do
        attribute :name, :string
      end
    end
    """

    assert [] = run_check(MissingTimestamps, source)
  end

  test "reports issue when no attributes section" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, data_layer: AshPostgres.DataLayer
    end
    """

    assert [issue] = run_check(MissingTimestamps, source)
    assert issue.message =~ "missing timestamps"
  end

  test "ignores non-Ash modules" do
    source = """
    defmodule MyApp.Utils do
      def hello, do: :world
    end
    """

    assert [] = run_check(MissingTimestamps, source)
  end
end
