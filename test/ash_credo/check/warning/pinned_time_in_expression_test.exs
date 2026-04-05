defmodule AshCredo.Check.Warning.PinnedTimeInExpressionTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Warning.PinnedTimeInExpression

  test "reports issue for ^Date.utc_today() in filter expr" do
    source = """
    defmodule MyApp.Subscription do
      use Ash.Resource, domain: MyApp.Billing

      actions do
        read :active do
          filter expr(
            status == :active and
            start_date <= ^Date.utc_today() and
            (is_nil(end_date) or end_date >= ^Date.utc_today())
          )
        end
      end
    end
    """

    issues = run_check(PinnedTimeInExpression, source)
    assert length(issues) == 2
    assert Enum.all?(issues, &(&1.message =~ "today()"))
    assert Enum.all?(issues, &(&1.trigger =~ "^Date.utc_today()"))
  end

  test "reports issue for ^DateTime.utc_now() in filter expr" do
    source = """
    defmodule MyApp.Session do
      use Ash.Resource, domain: MyApp.Auth

      actions do
        read :active do
          filter expr(expires_at >= ^DateTime.utc_now())
        end
      end
    end
    """

    assert [issue] = run_check(PinnedTimeInExpression, source)
    assert issue.message =~ "now()"
    assert issue.trigger =~ "^DateTime.utc_now()"
  end

  test "reports issue for ^NaiveDateTime.utc_now() in expr" do
    source = """
    defmodule MyApp.Event do
      use Ash.Resource, domain: MyApp.Calendar

      actions do
        read :upcoming do
          filter expr(starts_at >= ^NaiveDateTime.utc_now())
        end
      end
    end
    """

    assert [issue] = run_check(PinnedTimeInExpression, source)
    assert issue.message =~ "now()"
    assert issue.trigger =~ "^NaiveDateTime.utc_now()"
  end

  test "no issue when using today() in expr" do
    source = """
    defmodule MyApp.Subscription do
      use Ash.Resource, domain: MyApp.Billing

      actions do
        read :active do
          filter expr(
            status == :active and
            start_date <= today() and
            (is_nil(end_date) or end_date >= today())
          )
        end
      end
    end
    """

    assert [] = run_check(PinnedTimeInExpression, source)
  end

  test "no issue when using now() in expr" do
    source = """
    defmodule MyApp.Session do
      use Ash.Resource, domain: MyApp.Auth

      actions do
        read :active do
          filter expr(expires_at >= now())
        end
      end
    end
    """

    assert [] = run_check(PinnedTimeInExpression, source)
  end

  test "reports issue in calculation expr" do
    source = """
    defmodule MyApp.Subscription do
      use Ash.Resource, domain: MyApp.Billing

      calculations do
        calculate :is_active, :boolean, expr(
          status == :active and start_date <= ^Date.utc_today()
        )
      end
    end
    """

    assert [issue] = run_check(PinnedTimeInExpression, source)
    assert issue.message =~ "today()"
  end

  test "reports issue in validation expr" do
    source = """
    defmodule MyApp.Event do
      use Ash.Resource, domain: MyApp.Calendar

      validations do
        validate compare(:start_date, greater_than: expr(^Date.utc_today()))
      end
    end
    """

    assert [issue] = run_check(PinnedTimeInExpression, source)
    assert issue.message =~ "today()"
  end

  test "no issue for pinned non-time calls in expr" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        read :by_author do
          filter expr(author_id == ^arg(:author_id))
        end
      end
    end
    """

    assert [] = run_check(PinnedTimeInExpression, source)
  end

  test "no issue for non-Ash modules" do
    source = """
    defmodule MyApp.Utils do
      def check_date do
        Date.utc_today()
      end
    end
    """

    assert [] = run_check(PinnedTimeInExpression, source)
  end

  test "no issue when no expr calls exist" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      attributes do
        uuid_primary_key :id
        attribute :title, :string
      end
    end
    """

    assert [] = run_check(PinnedTimeInExpression, source)
  end

  test "ignores expr calls inside nested modules" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      defmodule Helpers do
        def stale_expr, do: expr(inserted_at >= ^DateTime.utc_now())
      end
    end
    """

    assert [] = run_check(PinnedTimeInExpression, source)
  end
end
