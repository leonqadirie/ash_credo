defmodule AshCredo.Check.Warning.MissingPrimaryKeyTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Warning.MissingPrimaryKey

  test "reports issue when no primary key" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, data_layer: AshPostgres.DataLayer

      attributes do
        attribute :title, :string
      end
    end
    """

    assert [issue] = run_check(MissingPrimaryKey, source)
    assert issue.message =~ "missing a primary key"
  end

  test "no issue with uuid_primary_key" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, data_layer: AshPostgres.DataLayer

      attributes do
        uuid_primary_key :id
        attribute :title, :string
      end
    end
    """

    assert [] = run_check(MissingPrimaryKey, source)
  end

  test "no issue with uuid_v7_primary_key" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, data_layer: AshPostgres.DataLayer

      attributes do
        uuid_v7_primary_key :id
        attribute :title, :string
      end
    end
    """

    assert [] = run_check(MissingPrimaryKey, source)
  end

  test "no issue with integer_primary_key" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, data_layer: AshPostgres.DataLayer

      attributes do
        integer_primary_key :id
        attribute :title, :string
      end
    end
    """

    assert [] = run_check(MissingPrimaryKey, source)
  end

  test "no issue with attribute primary_key?: true" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, data_layer: AshPostgres.DataLayer

      attributes do
        attribute :id, :uuid, primary_key?: true, allow_nil?: false
        attribute :title, :string
      end
    end
    """

    assert [] = run_check(MissingPrimaryKey, source)
  end

  test "no issue with primary_key?: true inside do block" do
    source = """
    defmodule MyApp.Token do
      use Ash.Resource, domain: MyApp.Accounts, data_layer: AshPostgres.DataLayer

      attributes do
        attribute :jti, :string do
          primary_key? true
          allow_nil? false
        end
      end
    end
    """

    assert [] = run_check(MissingPrimaryKey, source)
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

    assert [] = run_check(MissingPrimaryKey, source)
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

    assert [] = run_check(MissingPrimaryKey, source)
  end

  test "ignores non-Ash modules" do
    source = """
    defmodule MyApp.Utils do
      def hello, do: :world
    end
    """

    assert [] = run_check(MissingPrimaryKey, source)
  end

  test "no issue with composite primary key via belongs_to" do
    source = """
    defmodule MyApp.ArtistFollower do
      use Ash.Resource, domain: MyApp.Music, data_layer: AshPostgres.DataLayer

      relationships do
        belongs_to :artist, MyApp.Artist do
          primary_key? true
          allow_nil? false
        end

        belongs_to :follower, MyApp.User do
          primary_key? true
          allow_nil? false
        end
      end
    end
    """

    assert [] = run_check(MissingPrimaryKey, source)
  end

  test "reports issue when no attributes section" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog, data_layer: AshPostgres.DataLayer
    end
    """

    assert [issue] = run_check(MissingPrimaryKey, source)
    assert issue.message =~ "missing a primary key"
  end
end
