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
