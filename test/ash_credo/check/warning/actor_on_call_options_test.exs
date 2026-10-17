defmodule AshCredo.Check.Warning.ActorOnCallOptionsTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Warning.ActorOnCallOptions

  test "reports actor: on the call after a for_read pipe" do
    source = """
    defmodule MyApp.Posts do
      def list(current_user) do
        MyApp.Post
        |> Ash.Query.for_read(:read, %{})
        |> Ash.read!(actor: current_user)
      end
    end
    """

    assert [issue] = run_check(ActorOnCallOptions, source)
    assert issue.trigger == "actor"
    assert issue.line_no == 5
    assert issue.message =~ "for_read(..., actor: ...)"
  end

  test "reports tenant: on the call after a for_read pipe" do
    source = """
    defmodule MyApp.Posts do
      def list(tenant) do
        MyApp.Post
        |> Ash.Query.for_read(:read, %{})
        |> Ash.read!(tenant: tenant)
      end
    end
    """

    assert [issue] = run_check(ActorOnCallOptions, source)
    assert issue.trigger == "tenant"
  end

  test "reports both keys as separate issues" do
    source = """
    defmodule MyApp.Posts do
      def list(user, tenant) do
        MyApp.Post
        |> Ash.Query.for_read(:read, %{})
        |> Ash.read!(actor: user, tenant: tenant)
      end
    end
    """

    issues = run_check(ActorOnCallOptions, source)
    assert [_, _] = issues
    assert find_by_trigger(issues, "actor")
    assert find_by_trigger(issues, "tenant")
    assert sorted_lines(issues) == [5, 5]
  end

  test "reports actor: when the built query is bound to a variable" do
    source = """
    defmodule MyApp.Posts do
      def list(current_user) do
        query = Ash.Query.for_read(MyApp.Post, :read, %{})
        Ash.read!(query, actor: current_user)
      end
    end
    """

    assert [issue] = run_check(ActorOnCallOptions, source)
    assert issue.trigger == "actor"
  end

  test "reports actor: when the query passes through a variable chain" do
    source = """
    defmodule MyApp.Posts do
      def list(current_user) do
        built = Ash.Query.for_read(MyApp.Post, :read, %{})
        query = built
        Ash.read!(query, actor: current_user)
      end
    end
    """

    assert [issue] = run_check(ActorOnCallOptions, source)
    assert issue.trigger == "actor"
  end

  test "reports actor: when the builder is not the last pipe stage" do
    source = """
    defmodule MyApp.Posts do
      def list(current_user) do
        MyApp.Post
        |> Ash.Query.for_read(:read, %{})
        |> Ash.Query.limit(10)
        |> Ash.read!(actor: current_user)
      end
    end
    """

    assert [issue] = run_check(ActorOnCallOptions, source)
    assert issue.trigger == "actor"
  end

  test "reports actor: when the query variable is rebound through a pipe" do
    source = """
    defmodule MyApp.Posts do
      def list(current_user) do
        query = Ash.Query.for_read(MyApp.Post, :read, %{})
        query = query |> Ash.Query.limit(10)
        Ash.read!(query, actor: current_user)
      end
    end
    """

    assert [issue] = run_check(ActorOnCallOptions, source)
    assert issue.line_no == 5
  end

  test "reports actor: when the query variable is rebound through a direct call" do
    source = """
    defmodule MyApp.Posts do
      def list(current_user) do
        query = Ash.Query.for_read(MyApp.Post, :read, %{})
        query = Ash.Query.limit(query, 10)
        Ash.read!(query, actor: current_user)
      end
    end
    """

    assert [issue] = run_check(ActorOnCallOptions, source)
    assert issue.line_no == 5
  end

  test "no issue when a non-Ash call wraps the builder" do
    source = """
    defmodule MyApp.Posts do
      def list(current_user) do
        query = MyApp.Queries.scoped(Ash.Query.for_read(MyApp.Post, :read, %{}))
        Ash.read!(query, actor: current_user)
      end
    end
    """

    # The helper may return anything, so the subject's origin is not visible.
    assert [] = run_check(ActorOnCallOptions, source)
  end

  test "reports actor: when a fn parameter shadows the rebound variable" do
    source = """
    defmodule MyApp.Posts do
      def list(current_user) do
        query = Ash.Query.for_read(MyApp.Post, :read, %{})
        query = query |> Ash.Query.after_action(fn query, records -> {:ok, records} end)
        Ash.read!(query, actor: current_user)
      end
    end
    """

    assert [issue] = run_check(ActorOnCallOptions, source)
    assert issue.line_no == 5
  end

  test "no issue for a rebound variable whose first value is not visible" do
    source = """
    defmodule MyApp.Posts do
      def list(query, current_user) do
        query = query |> Ash.Query.limit(10)
        query = query |> Ash.Query.offset(5)
        Ash.read!(query, actor: current_user)
      end
    end
    """

    assert [] = run_check(ActorOnCallOptions, source)
  end

  test "no issue when a fn parameter shadows a builder-bound variable" do
    source = """
    defmodule MyApp.Posts do
      def list(queries, current_user) do
        query = Ash.Query.for_read(MyApp.Post, :read, %{}, actor: current_user)

        Enum.map(queries, fn query ->
          query = Ash.Query.limit(query, 1)
          Ash.read!(query, actor: current_user)
        end)
      end
    end
    """

    assert [] = run_check(ActorOnCallOptions, source)
  end

  test "no issue for a record that an action call returned" do
    source = """
    defmodule MyApp.Posts do
      def recreate(current_user) do
        post = MyApp.Post |> Ash.Changeset.for_create(:create, %{}) |> Ash.create!()
        Ash.destroy!(post, actor: current_user)

        other = MyApp.Post |> Ash.Changeset.for_create(:create, %{}) |> Ash.create!()
        other = other |> Ash.load!(:comments)
        Ash.destroy!(other, actor: current_user)
      end
    end
    """

    assert [] = run_check(ActorOnCallOptions, source)
  end

  test "no issue for a value a builder getter returned" do
    source = """
    defmodule MyApp.Posts do
      def import(post, current_user) do
        input = Ash.ActionInput.for_action(MyApp.Post, :import, %{post: post})
        record = Ash.ActionInput.get_argument(input, :post)
        Ash.update!(record, %{}, actor: current_user)

        piped =
          MyApp.Post
          |> Ash.ActionInput.for_action(:import, %{post: post})
          |> Ash.ActionInput.get_argument(:post)

        Ash.update!(piped, %{}, actor: current_user)
      end
    end
    """

    assert [] = run_check(ActorOnCallOptions, source)
  end

  test "no issue when the subject is built without a builder" do
    source = """
    defmodule MyApp.Posts do
      def list(current_user) do
        MyApp.Post
        |> Ash.Query.limit(10)
        |> Ash.read!(actor: current_user)
      end
    end
    """

    assert [] = run_check(ActorOnCallOptions, source)
  end

  test "no issue when the options are a variable" do
    source = """
    defmodule MyApp.Posts do
      def list(opts) do
        MyApp.Post
        |> Ash.Query.for_read(:read, %{})
        |> Ash.read!(opts)
      end
    end
    """

    assert [] = run_check(ActorOnCallOptions, source)
  end

  test "reports actor: on create after a for_create changeset" do
    source = """
    defmodule MyApp.Posts do
      def create(params, current_user) do
        MyApp.Post
        |> Ash.Changeset.for_create(:create, params)
        |> Ash.create!(actor: current_user)
      end
    end
    """

    assert [issue] = run_check(ActorOnCallOptions, source)
    assert issue.message =~ "Ash.create!"
  end

  test "reports actor: on an aggregate call after a for_read pipe" do
    source = """
    defmodule MyApp.Posts do
      def total_likes(current_user) do
        MyApp.Post
        |> Ash.Query.for_read(:read, %{})
        |> Ash.sum(:likes, actor: current_user)
      end
    end
    """

    assert [issue] = run_check(ActorOnCallOptions, source)
    assert issue.trigger == "actor"
    assert issue.message =~ "Ash.sum"
  end

  test "reports tenant: on Ash.aggregate! when the query is bound to a variable" do
    source = """
    defmodule MyApp.Posts do
      def stats(tenant) do
        query = Ash.Query.for_read(MyApp.Post, :read, %{})
        Ash.aggregate!(query, {:count, :count}, tenant: tenant)
      end
    end
    """

    assert [issue] = run_check(ActorOnCallOptions, source)
    assert issue.trigger == "tenant"
    assert issue.message =~ "Ash.aggregate!"
  end

  test "no issue for an aggregate without a pre-built subject (sanctioned form)" do
    source = """
    defmodule MyApp.Posts do
      def total_likes(current_user) do
        Ash.sum(MyApp.Post, :likes, actor: current_user)
      end
    end
    """

    assert [] = run_check(ActorOnCallOptions, source)
  end

  test "no issue for a 2-arg aggregate whose spec list names an :actor aggregate" do
    # Without a trailing opts argument, the aggregate-spec list is a
    # required argument, not the options of the call.
    source = """
    defmodule MyApp.Posts do
      def stats do
        MyApp.Post
        |> Ash.Query.for_read(:read, %{})
        |> Ash.aggregate([{:actor, :count}])
      end
    end
    """

    assert [] = run_check(ActorOnCallOptions, source)
  end

  test "reports actor: on read_first after a for_read pipe" do
    source = """
    defmodule MyApp.Posts do
      def newest(current_user) do
        MyApp.Post
        |> Ash.Query.for_read(:read, %{})
        |> Ash.read_first(actor: current_user)
      end
    end
    """

    assert [issue] = run_check(ActorOnCallOptions, source)
    assert issue.trigger == "actor"
    assert issue.message =~ "Ash.read_first"
  end

  test "reports actor: on data_layer_query (delegates to read)" do
    source = """
    defmodule MyApp.Posts do
      def raw_query(current_user) do
        MyApp.Post
        |> Ash.Query.for_read(:read, %{})
        |> Ash.data_layer_query(actor: current_user)
      end
    end
    """

    assert [issue] = run_check(ActorOnCallOptions, source)
    assert issue.trigger == "actor"
    assert issue.message =~ "Ash.data_layer_query"
  end

  test "reports actor: on bulk_update after a for_read pipe" do
    source = """
    defmodule MyApp.Posts do
      def archive_all(current_user) do
        MyApp.Post
        |> Ash.Query.for_read(:read, %{})
        |> Ash.bulk_update(:archive, %{archived: true}, actor: current_user)
      end
    end
    """

    assert [issue] = run_check(ActorOnCallOptions, source)
    assert issue.trigger == "actor"
    assert issue.message =~ "Ash.bulk_update"
  end

  test "reports tenant: on bulk_destroy! when the query is bound to a variable" do
    source = """
    defmodule MyApp.Posts do
      def purge(tenant) do
        query = Ash.Query.for_read(MyApp.Post, :read, %{})
        Ash.bulk_destroy!(query, :destroy, %{}, tenant: tenant)
      end
    end
    """

    assert [issue] = run_check(ActorOnCallOptions, source)
    assert issue.trigger == "tenant"
    assert issue.message =~ "Ash.bulk_destroy!"
  end

  test "no issue for a bulk_update whose keyword input names an :actor field" do
    # Without a trailing opts argument, the input keyword list is a
    # required argument, not the options of the call.
    source = """
    defmodule MyApp.Posts do
      def reassign(new_actor) do
        MyApp.Post
        |> Ash.Query.for_read(:read, %{})
        |> Ash.bulk_update(:reassign, [actor: new_actor])
      end
    end
    """

    assert [] = run_check(ActorOnCallOptions, source)
  end

  test "resolves aliased builder modules" do
    source = """
    defmodule MyApp.Posts do
      alias Ash.Query, as: Q

      def list(current_user) do
        MyApp.Post
        |> Q.for_read(:read, %{})
        |> Ash.read!(actor: current_user)
      end
    end
    """

    assert [issue] = run_check(ActorOnCallOptions, source)
    assert issue.trigger == "actor"
  end

  test "no issue when the actor is set on the builder" do
    source = """
    defmodule MyApp.Posts do
      def list(current_user) do
        MyApp.Post
        |> Ash.Query.for_read(:read, %{}, actor: current_user)
        |> Ash.read!()
      end
    end
    """

    assert [] = run_check(ActorOnCallOptions, source)
  end

  test "no issue for actor: without a pre-built subject (sanctioned form)" do
    source = """
    defmodule MyApp.Posts do
      def list(current_user) do
        Ash.read!(MyApp.Post, actor: current_user)
      end
    end
    """

    assert [] = run_check(ActorOnCallOptions, source)
  end

  test "no issue for scope: at call time (sanctioned context inheritance)" do
    source = """
    defmodule MyApp.Posts do
      def list(context) do
        MyApp.Post
        |> Ash.Query.for_read(:read, %{})
        |> Ash.read!(scope: context)
      end
    end
    """

    assert [] = run_check(ActorOnCallOptions, source)
  end

  test "no issue for code interface calls with actor:" do
    source = """
    defmodule MyApp.Web do
      def list(current_user) do
        MyApp.Blog.list_posts!(actor: current_user)
      end
    end
    """

    assert [] = run_check(ActorOnCallOptions, source)
  end

  test "no issue when the subject origin is not visible" do
    source = """
    defmodule MyApp.Posts do
      def run(query, current_user) do
        Ash.read!(query, actor: current_user)
      end
    end
    """

    assert [] = run_check(ActorOnCallOptions, source)
  end

  test "ignores non-Ash modules" do
    source = """
    defmodule MyApp.Utils do
      def read!(subject, opts), do: {subject, opts}

      def run(q, user) do
        MyApp.Utils.read!(q, actor: user)
      end
    end
    """

    assert [] = run_check(ActorOnCallOptions, source)
  end
end
