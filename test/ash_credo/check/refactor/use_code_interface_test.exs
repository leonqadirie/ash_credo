defmodule AshCredo.Check.Refactor.UseCodeInterfaceTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Refactor.UseCodeInterface

  # ── Pattern A: action in keyword opts ──

  test "flags Ash.read with literal resource and action" do
    source = """
    defmodule MyApp.Accounts do
      def list_published do
        Ash.read(MyApp.Post, action: :published)
      end
    end
    """

    assert [issue] = run_check(UseCodeInterface, source)
    assert issue.trigger == "Ash.read"
    assert issue.message =~ "code interface"
  end

  test "flags Ash.read! with literal resource and action" do
    source = """
    defmodule MyApp.Accounts do
      def list_published do
        Ash.read!(MyApp.Post, action: :published)
      end
    end
    """

    assert [issue] = run_check(UseCodeInterface, source)
    assert issue.trigger == "Ash.read!"
  end

  test "flags Ash.get! with literal resource and action in opts" do
    source = """
    defmodule MyApp.Accounts do
      def find_post(id) do
        Ash.get!(MyApp.Post, id, action: :by_id)
      end
    end
    """

    assert [issue] = run_check(UseCodeInterface, source)
    assert issue.trigger == "Ash.get!"
  end

  test "flags Ash.stream! with literal resource and action" do
    source = """
    defmodule MyApp.Accounts do
      def stream_active do
        Ash.stream!(MyApp.Post, action: :active)
      end
    end
    """

    assert [issue] = run_check(UseCodeInterface, source)
    assert issue.trigger == "Ash.stream!"
  end

  test "flags when action is mixed with other opts" do
    source = """
    defmodule MyApp.Accounts do
      def list_published(actor) do
        Ash.read!(MyApp.Post, actor: actor, action: :published)
      end
    end
    """

    assert [issue] = run_check(UseCodeInterface, source)
    assert issue.trigger == "Ash.read!"
  end

  # ── Pattern B: bulk operations ──

  test "flags Ash.bulk_create with literal resource and action" do
    source = """
    defmodule MyApp.Importer do
      def import(inputs) do
        Ash.bulk_create(inputs, MyApp.Post, :import)
      end
    end
    """

    assert [issue] = run_check(UseCodeInterface, source)
    assert issue.trigger == "Ash.bulk_create"
  end

  test "flags Ash.bulk_update when query variable originates from literal resource" do
    source = """
    defmodule MyApp.Admin do
      def archive_all do
        query = Ash.Query.for_read(MyApp.Post, :published)
        Ash.bulk_update(query, :archive, %{})
      end
    end
    """

    issues = run_check(UseCodeInterface, source)
    assert Enum.any?(issues, &(&1.trigger == "Ash.bulk_update"))
  end

  test "flags Ash.bulk_update when traced query origin uses an alias" do
    source = """
    defmodule MyApp.Admin do
      def archive_all do
        alias Ash.Query, as: QueryDsl

        query = QueryDsl.for_read(MyApp.Post, :published)
        Ash.bulk_update(query, :archive, %{})
      end
    end
    """

    issues = run_check(UseCodeInterface, source)
    assert Enum.any?(issues, &(&1.trigger == "Ash.bulk_update"))
  end

  test "flags piped Ash.bulk_destroy! when query originates from literal resource" do
    source = """
    defmodule MyApp.Admin do
      def cleanup do
        MyApp.Post
        |> Ash.Query.for_read(:published)
        |> Ash.bulk_destroy!(:cleanup, %{})
      end
    end
    """

    issues = run_check(UseCodeInterface, source)
    assert Enum.any?(issues, &(&1.trigger == "Ash.bulk_destroy!"))
  end

  test "flags Ash.bulk_update when stream variable originates from literal resource" do
    source = """
    defmodule MyApp.Admin do
      def archive_stream do
        stream = Ash.stream!(MyApp.Post, action: :published)
        Ash.bulk_update(stream, :archive, %{})
      end
    end
    """

    issues = run_check(UseCodeInterface, source)
    assert Enum.any?(issues, &(&1.trigger == "Ash.bulk_update"))
  end

  # ── Pattern C: builder functions ──

  test "flags Ash.Changeset.for_create with literal resource and action" do
    source = """
    defmodule MyApp.Accounts do
      def create_post(params) do
        Ash.Changeset.for_create(MyApp.Post, :create, params)
      end
    end
    """

    assert [issue] = run_check(UseCodeInterface, source)
    assert issue.trigger == "Ash.Changeset.for_create"
  end

  test "flags Ash.Query.for_read with literal resource and action" do
    source = """
    defmodule MyApp.Accounts do
      def published_query do
        Ash.Query.for_read(MyApp.Post, :published)
      end
    end
    """

    assert [issue] = run_check(UseCodeInterface, source)
    assert issue.trigger == "Ash.Query.for_read"
  end

  test "flags Ash.ActionInput.for_action with literal resource and action" do
    source = """
    defmodule MyApp.Notifier do
      def notify do
        Ash.ActionInput.for_action(MyApp.Post, :notify)
      end
    end
    """

    assert [issue] = run_check(UseCodeInterface, source)
    assert issue.trigger == "Ash.ActionInput.for_action"
  end

  test "flags aliased Ash.Query.for_read" do
    source = """
    defmodule MyApp.Accounts do
      alias Ash.Query

      def published_query do
        Query.for_read(MyApp.Post, :published)
      end
    end
    """

    assert [issue] = run_check(UseCodeInterface, source)
    assert issue.trigger == "Ash.Query.for_read"
  end

  # ── Multiple issues ──

  test "reports multiple issues for multiple calls" do
    source = """
    defmodule MyApp.Accounts do
      def list_published do
        Ash.read!(MyApp.Post, action: :published)
      end

      def import(inputs) do
        Ash.bulk_create(inputs, MyApp.Post, :import)
      end
    end
    """

    assert [_, _] = run_check(UseCodeInterface, source)
  end

  # ── Should NOT flag ──

  test "no issue when no action specified" do
    source = """
    defmodule MyApp.Accounts do
      def list_posts do
        Ash.read(MyApp.Post)
      end
    end
    """

    assert [] = run_check(UseCodeInterface, source)
  end

  test "no issue when resource is a variable" do
    source = """
    defmodule MyApp.Accounts do
      def list(resource) do
        Ash.read!(resource, action: :published)
      end
    end
    """

    assert [] = run_check(UseCodeInterface, source)
  end

  test "no issue when action is a variable" do
    source = """
    defmodule MyApp.Accounts do
      def list(action) do
        Ash.read!(MyApp.Post, action: action)
      end
    end
    """

    assert [] = run_check(UseCodeInterface, source)
  end

  test "flags piped literal resource with action in opts" do
    source = """
    defmodule MyApp.Accounts do
      def list_published do
        MyApp.Post
        |> Ash.read!(action: :published)
      end
    end
    """

    assert [issue] = run_check(UseCodeInterface, source)
    assert issue.trigger == "Ash.read!"
  end

  test "flags piped literal resource into builder" do
    source = """
    defmodule MyApp.Accounts do
      def published_query do
        MyApp.Post
        |> Ash.Query.for_read(:published)
      end
    end
    """

    assert [issue] = run_check(UseCodeInterface, source)
    assert issue.trigger == "Ash.Query.for_read"
  end

  test "no issue when piped value is not a literal module" do
    source = """
    defmodule MyApp.Accounts do
      def list_published(query) do
        query
        |> Ash.read!(action: :published)
      end
    end
    """

    assert [] = run_check(UseCodeInterface, source)
  end

  test "no issue for chained pipe where intermediate transforms the resource" do
    source = """
    defmodule MyApp.Accounts do
      def list_published do
        MyApp.Post
        |> Ash.Query.filter(active: true)
        |> Ash.read!(action: :published)
      end
    end
    """

    issues = run_check(UseCodeInterface, source)
    # Only the Ash.read! should NOT be flagged (its piped arg is a query, not a literal module).
    # No Ash.Query.filter match either (not in our classification).
    assert [] = issues
  end

  test "no issue for bulk with variable resource" do
    source = """
    defmodule MyApp.Importer do
      def import(inputs, resource) do
        Ash.bulk_create(inputs, resource, :import)
      end
    end
    """

    assert [] = run_check(UseCodeInterface, source)
  end

  test "no issue for bulk with variable action" do
    source = """
    defmodule MyApp.Importer do
      def import(inputs, action) do
        Ash.bulk_create(inputs, MyApp.Post, action)
      end
    end
    """

    assert [] = run_check(UseCodeInterface, source)
  end

  test "no issue for bulk_update with variable query" do
    source = """
    defmodule MyApp.Admin do
      def archive_all(query) do
        Ash.bulk_update(query, :archive, %{})
      end
    end
    """

    assert [] = run_check(UseCodeInterface, source)
  end

  test "no issue for bulk_destroy with unresolved local query provenance" do
    source = """
    defmodule MyApp.Admin do
      def cleanup do
        query = build_query(MyApp.Post)
        Ash.bulk_destroy(query, :cleanup, %{})
      end
    end
    """

    assert [] = run_check(UseCodeInterface, source)
  end

  test "no issue for invalid bulk_update form with direct resource literal" do
    source = """
    defmodule MyApp.Admin do
      def archive_all do
        Ash.bulk_update(MyApp.Post, :archive, %{})
      end
    end
    """

    assert [] = run_check(UseCodeInterface, source)
  end

  test "no issue for non-Ash calls" do
    source = """
    defmodule MyApp.Accounts do
      def list_published do
        SomeOtherLib.read(MyApp.Post, action: :published)
      end
    end
    """

    assert [] = run_check(UseCodeInterface, source)
  end

  test "no issue when opts have no action key" do
    source = """
    defmodule MyApp.Accounts do
      def list_posts(actor) do
        Ash.read!(MyApp.Post, actor: actor)
      end
    end
    """

    assert [] = run_check(UseCodeInterface, source)
  end
end
