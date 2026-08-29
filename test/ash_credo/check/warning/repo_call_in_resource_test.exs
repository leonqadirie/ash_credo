defmodule AshCredo.Check.Warning.RepoCallInResourceTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Warning.RepoCallInResource

  test "reports issue for Repo.query! in a change module" do
    source = """
    defmodule MyApp.Order.Changes.AssignStops do
      use Ash.Resource.Change

      def change(changeset, _opts, _context) do
        MyApp.Repo.query!("UPDATE orders SET x = 1", [])
        changeset
      end
    end
    """

    assert [issue] = run_check(RepoCallInResource, source)
    assert issue.trigger == "MyApp.Repo.query!"
    assert issue.message =~ "Ash.Resource.Change"
    assert issue.line_no == 5
  end

  test "reports issue for aliased Repo call" do
    source = """
    defmodule MyApp.Order.Changes.AssignStops do
      use Ash.Resource.Change

      alias MyApp.Repo

      def change(changeset, _opts, _context) do
        Repo.update_all(query(), set: [x: 1])
        changeset
      end
    end
    """

    assert [issue] = run_check(RepoCallInResource, source)
    assert issue.trigger == "Repo.update_all"
  end

  test "reports issue for Ecto.Adapters.SQL.query!" do
    source = """
    defmodule MyApp.Order.Changes.AssignStops do
      use Ash.Resource.Change

      def change(changeset, _opts, _context) do
        Ecto.Adapters.SQL.query!(MyApp.Repo, "SELECT 1", [])
        changeset
      end
    end
    """

    assert [issue] = run_check(RepoCallInResource, source)
    assert issue.trigger == "Ecto.Adapters.SQL.query!"
  end

  test "reports issue for Ecto.Adapters.SQL aliased to SQL" do
    source = """
    defmodule MyApp.Order.Changes.AssignStops do
      use Ash.Resource.Change

      alias Ecto.Adapters.SQL

      def change(changeset, _opts, _context) do
        SQL.query!(MyApp.Repo, "SELECT 1", [])
        changeset
      end
    end
    """

    assert [issue] = run_check(RepoCallInResource, source)
    assert issue.trigger == "SQL.query!"
  end

  test "reports issues in each extension point module kind" do
    for {use_module, label} <- [
          {"Ash.Resource.Change", "Ash.Resource.Change"},
          {"Ash.Resource.Validation", "Ash.Resource.Validation"},
          {"Ash.Resource.Preparation", "Ash.Resource.Preparation"},
          {"Ash.Resource.Calculation", "Ash.Resource.Calculation"},
          {"Ash.Resource.Actions.Implementation", "Ash.Resource.Actions.Implementation"}
        ] do
      source = """
      defmodule MyApp.Thing do
        use #{use_module}

        def helper do
          MyApp.Repo.delete_all(MyApp.Order)
        end
      end
      """

      assert [issue] = run_check(RepoCallInResource, source),
             "expected an issue for #{use_module}"

      assert issue.message =~ label
    end
  end

  test "reports issue for a Repo call inside a resource module" do
    source = """
    defmodule MyApp.Order do
      use Ash.Resource, domain: MyApp.Logistics

      actions do
        update :sync do
          change fn changeset, _context ->
            MyApp.Repo.insert_all("order_logs", [%{order_id: 1}])
            changeset
          end
        end
      end
    end
    """

    assert [issue] = run_check(RepoCallInResource, source)
    assert issue.trigger == "MyApp.Repo.insert_all"
    assert issue.message =~ "Ash.Resource"
  end

  test "reports one issue per call site" do
    source = """
    defmodule MyApp.Order.Changes.AssignStops do
      use Ash.Resource.Change

      def change(changeset, _opts, _context) do
        MyApp.Repo.query!("UPDATE a SET x = 1", [])
        MyApp.Repo.query!("UPDATE b SET x = 1", [])
        changeset
      end
    end
    """

    issues = run_check(RepoCallInResource, source)
    assert sorted_lines(issues) == [5, 6]
  end

  test "no issue for Repo calls in a plain module" do
    source = """
    defmodule MyApp.Reports do
      def totals do
        MyApp.Repo.query!("SELECT count(*) FROM orders", [])
      end
    end
    """

    assert [] = run_check(RepoCallInResource, source)
  end

  test "no issue for Repo.transaction wrapping Ash calls" do
    source = """
    defmodule MyApp.Order.Changes.AssignStops do
      use Ash.Resource.Change

      def change(changeset, _opts, _context) do
        MyApp.Repo.transaction(fn ->
          Ash.update!(changeset)
        end)

        changeset
      end
    end
    """

    assert [] = run_check(RepoCallInResource, source)
  end

  test "still flags a query executor inside Repo.transaction" do
    source = """
    defmodule MyApp.Order.Changes.AssignStops do
      use Ash.Resource.Change

      def change(changeset, _opts, _context) do
        MyApp.Repo.transaction(fn ->
          MyApp.Repo.update_all(query(), set: [x: 1])
        end)

        changeset
      end
    end
    """

    assert [issue] = run_check(RepoCallInResource, source)
    assert issue.trigger == "MyApp.Repo.update_all"
  end

  test "no issue for non-flagged functions on a Repo module" do
    source = """
    defmodule MyApp.Order.Changes.AssignStops do
      use Ash.Resource.Change

      def change(changeset, _opts, _context) do
        MyApp.Repo.aggregate(MyApp.Order, :count)
        changeset
      end
    end
    """

    assert [] = run_check(RepoCallInResource, source)
  end

  test "no issue for flagged function names on non-Repo modules" do
    source = """
    defmodule MyApp.Order.Changes.AssignStops do
      use Ash.Resource.Change

      def change(changeset, _opts, _context) do
        MyApp.Metrics.query!("orders.updated")
        changeset
      end
    end
    """

    assert [] = run_check(RepoCallInResource, source)
  end

  test "attributes a call in a nested change module to that module, not the resource" do
    source = """
    defmodule MyApp.Order do
      use Ash.Resource, domain: MyApp.Logistics

      defmodule AssignStops do
        use Ash.Resource.Change

        def change(changeset, _opts, _context) do
          MyApp.Repo.query!("UPDATE orders SET x = 1", [])
          changeset
        end
      end
    end
    """

    assert [issue] = run_check(RepoCallInResource, source)
    assert issue.message =~ "Ash.Resource.Change"
  end

  test "no issue in a plain module nested inside a resource" do
    source = """
    defmodule MyApp.Order do
      use Ash.Resource, domain: MyApp.Logistics

      defmodule SqlHelpers do
        def raw do
          MyApp.Repo.query!("SELECT 1", [])
        end
      end
    end
    """

    assert [] = run_check(RepoCallInResource, source)
  end

  test "no issue for Repo calls inside a quote block" do
    source = """
    defmodule MyApp.Order.Changes.Helpers do
      use Ash.Resource.Change

      defmacro fetch_raw(sql) do
        quote do
          MyApp.Repo.query!(unquote(sql), [])
        end
      end
    end
    """

    assert [] = run_check(RepoCallInResource, source)
  end

  test "resolves __MODULE__-relative Repo references against the enclosing module" do
    source = """
    defmodule MyApp.Order.Changes.AssignStops do
      use Ash.Resource.Change

      def change(changeset, _opts, _context) do
        __MODULE__.Repo.query!("SELECT 1")
        changeset
      end
    end
    """

    assert [issue] = run_check(RepoCallInResource, source)
    assert issue.trigger == "__MODULE__.Repo.query!"
  end

  test "reports issue when the use target is reached through an alias" do
    source = """
    defmodule MyApp.Order.Changes.AssignStops do
      alias Ash.Resource.Change

      use Change

      def change(changeset, _opts, _context) do
        MyApp.Repo.query!("SELECT 1", [])
        changeset
      end
    end
    """

    assert [issue] = run_check(RepoCallInResource, source)
    assert issue.message =~ "Ash.Resource.Change"
  end

  test "reports issue when the use options are not a literal keyword list" do
    source = """
    defmodule MyApp.Order.Changes.AssignStops do
      @opts []
      use Ash.Resource.Change, @opts

      def change(changeset, _opts, _context) do
        MyApp.Repo.query!("SELECT 1", [])
        changeset
      end
    end
    """

    assert [issue] = run_check(RepoCallInResource, source)
    assert issue.message =~ "Ash.Resource.Change"
  end

  test "no issue for a change module defined inside a quote block" do
    source = """
    defmodule MyApp.ChangeTemplate do
      defmacro make_change do
        quote do
          defmodule MyApp.Generated do
            use Ash.Resource.Change

            def change(changeset, _opts, _context) do
              MyApp.Repo.query!("SELECT 1", [])
              changeset
            end
          end
        end
      end
    end
    """

    assert [] = run_check(RepoCallInResource, source)
  end

  describe "flagged_functions param" do
    test "extra entries widen detection" do
      source = """
      defmodule MyApp.Order.Changes.AssignStops do
        use Ash.Resource.Change

        def change(changeset, _opts, _context) do
          MyApp.Repo.insert(%MyApp.OrderLog{})
          changeset
        end
      end
      """

      assert [] = run_check(RepoCallInResource, source)

      assert [issue] = run_check(RepoCallInResource, source, flagged_functions: [:insert])
      assert issue.trigger == "MyApp.Repo.insert"
    end

    test "removed entries narrow detection" do
      source = """
      defmodule MyApp.Order.Changes.AssignStops do
        use Ash.Resource.Change

        def change(changeset, _opts, _context) do
          MyApp.Repo.query!("SELECT 1", [])
          changeset
        end
      end
      """

      assert [] = run_check(RepoCallInResource, source, flagged_functions: [:update_all])
    end

    test "accepts a single atom instead of a list" do
      source = """
      defmodule MyApp.Order.Changes.AssignStops do
        use Ash.Resource.Change

        def change(changeset, _opts, _context) do
          MyApp.Repo.query!("SELECT 1", [])
          changeset
        end
      end
      """

      assert [issue] = run_check(RepoCallInResource, source, flagged_functions: :query!)
      assert issue.trigger == "MyApp.Repo.query!"
    end
  end

  describe "repo_names param" do
    test "a repo not named Repo passes by default" do
      source = """
      defmodule MyApp.Order.Changes.AssignStops do
        use Ash.Resource.Change

        def change(changeset, _opts, _context) do
          MyApp.Database.update_all(query(), set: [x: 1])
          changeset
        end
      end
      """

      assert [] = run_check(RepoCallInResource, source)
    end

    test "extra names widen detection" do
      source = """
      defmodule MyApp.Order.Changes.AssignStops do
        use Ash.Resource.Change

        def change(changeset, _opts, _context) do
          MyApp.Database.update_all(query(), set: [x: 1])
          changeset
        end
      end
      """

      assert [issue] =
               run_check(RepoCallInResource, source, repo_names: [:Repo, :Database])

      assert issue.trigger == "MyApp.Database.update_all"
    end

    test "accepts a single atom instead of a list" do
      source = """
      defmodule MyApp.Order.Changes.AssignStops do
        use Ash.Resource.Change

        def change(changeset, _opts, _context) do
          MyApp.Database.update_all(query(), set: [x: 1])
          changeset
        end
      end
      """

      assert [issue] = run_check(RepoCallInResource, source, repo_names: :Database)
      assert issue.trigger == "MyApp.Database.update_all"
    end

    test "regex entries match against the last segment" do
      source = """
      defmodule MyApp.Order.Changes.AssignStops do
        use Ash.Resource.Change

        def change(changeset, _opts, _context) do
          MyApp.AnalyticsRepo.update_all(query(), set: [x: 1])
          changeset
        end
      end
      """

      assert [] = run_check(RepoCallInResource, source)

      assert [issue] = run_check(RepoCallInResource, source, repo_names: [~r/Repo$/])
      assert issue.trigger == "MyApp.AnalyticsRepo.update_all"
    end

    test "resolves a repo renamed via alias as: to its real name" do
      source = """
      defmodule MyApp.Order.Changes.AssignStops do
        use Ash.Resource.Change

        alias MyApp.Repo, as: DB

        def change(changeset, _opts, _context) do
          DB.query!("SELECT 1", [])
          changeset
        end
      end
      """

      assert [issue] = run_check(RepoCallInResource, source)
      assert issue.trigger == "DB.query!"
    end

    test "matches on the resolved module, not the written alias" do
      source = """
      defmodule MyApp.Order.Changes.AssignStops do
        use Ash.Resource.Change

        alias MyApp.Metrics, as: Repo

        def change(changeset, _opts, _context) do
          Repo.query!("orders.updated")
          changeset
        end
      end
      """

      assert [] = run_check(RepoCallInResource, source)
    end

    test "Ecto.Adapters.SQL is flagged independently of repo_names" do
      source = """
      defmodule MyApp.Order.Changes.AssignStops do
        use Ash.Resource.Change

        def change(changeset, _opts, _context) do
          Ecto.Adapters.SQL.query!(MyApp.Repo, "SELECT 1", [])
          changeset
        end
      end
      """

      assert [issue] = run_check(RepoCallInResource, source, repo_names: [])
      assert issue.trigger == "Ecto.Adapters.SQL.query!"
    end
  end

  describe "excluded_paths" do
    test "skips files under test/ by default" do
      source = """
      defmodule MyApp.OrderTest.FakeChange do
        use Ash.Resource.Change

        def change(changeset, _opts, _context) do
          MyApp.Repo.query!("SELECT 1", [])
          changeset
        end
      end
      """

      assert [] =
               run_check(RepoCallInResource, source, __filename__: "test/support/fake_change.ex")
    end

    test "respects an empty excluded_paths override" do
      source = """
      defmodule MyApp.OrderTest.FakeChange do
        use Ash.Resource.Change

        def change(changeset, _opts, _context) do
          MyApp.Repo.query!("SELECT 1", [])
          changeset
        end
      end
      """

      assert [issue] =
               run_check(RepoCallInResource, source,
                 __filename__: "test/support/fake_change.ex",
                 excluded_paths: []
               )

      assert issue.trigger == "MyApp.Repo.query!"
    end
  end
end
