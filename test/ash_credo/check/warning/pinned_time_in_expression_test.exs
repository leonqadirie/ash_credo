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
    assert [_, _] = issues
    assert sorted_lines(issues) == [8, 9]

    Enum.each(issues, fn issue ->
      assert issue.message =~ "today()"
      assert issue.trigger =~ "^Date.utc_today()"
    end)
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

  test "reports pinned time called through an alias rename" do
    source = """
    defmodule MyApp.Session do
      use Ash.Resource, domain: MyApp.Auth

      alias DateTime, as: DT

      actions do
        read :active do
          filter expr(expires_at >= ^DT.utc_now())
        end
      end
    end
    """

    assert [issue] = run_check(PinnedTimeInExpression, source)
    assert issue.message =~ "now()"
    assert issue.trigger == "^DT.utc_now()"
    assert issue.line_no == 8
  end

  test "reports Elixir-prefixed pinned forms, aliased and fully qualified" do
    source = """
    defmodule MyApp.Session do
      use Ash.Resource, domain: MyApp.Auth

      alias Elixir.DateTime

      actions do
        read :active do
          filter expr(expires_at >= ^DateTime.utc_now())
        end

        read :expired do
          filter expr(expires_at < ^Elixir.DateTime.utc_now())
        end
      end
    end
    """

    issues = run_check(PinnedTimeInExpression, source)
    assert sorted_lines(issues) == [8, 12]

    assert Enum.map(issues, & &1.trigger) |> Enum.sort() ==
             ["^DateTime.utc_now()", "^Elixir.DateTime.utc_now()"]
  end

  test "no issue for a differently-named module's utc_now" do
    source = """
    defmodule MyApp.Venue do
      use Ash.Resource, domain: MyApp.Places

      alias MyApp.Clock

      actions do
        read :open_now do
          filter expr(opens_at <= ^Clock.utc_now())
          filter expr(closes_at >= ^MyApp.Clock.utc_now())
        end
      end
    end
    """

    assert [] = run_check(PinnedTimeInExpression, source)
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

  test "no issue for expr inside function bodies" do
    # Ash.Expr.expr/1 splices the pinned code into its call site, so in a
    # function the pin re-evaluates on every call and is not frozen.
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      import Ash.Expr

      def stale_query, do: Ash.Query.filter(__MODULE__, ^stale_expr())
      defp stale_expr, do: expr(inserted_at >= ^DateTime.utc_now())
    end
    """

    assert [] = run_check(PinnedTimeInExpression, source)
  end

  test "no issue for expr inside anonymous functions in the DSL" do
    source = """
    defmodule MyApp.Session do
      use Ash.Resource, domain: MyApp.Auth

      actions do
        read :active do
          prepare fn query, _context ->
            Ash.Query.filter(query, expr(expires_at >= ^DateTime.utc_now()))
          end
        end
      end
    end
    """

    assert [] = run_check(PinnedTimeInExpression, source)
  end

  test "reports pinned time in an immediately-invoked fn in DSL position" do
    # The fn runs while the resource compiles, so the pin IS frozen here -
    # unlike a stored fn, which runs per invocation.
    source = """
    defmodule MyApp.Session do
      use Ash.Resource, domain: MyApp.Auth

      actions do
        read :active do
          filter (fn -> expr(expires_at >= ^DateTime.utc_now()) end).()
        end
      end
    end
    """

    assert [issue] = run_check(PinnedTimeInExpression, source)
    assert issue.trigger == "^DateTime.utc_now()"
  end

  test "reports pinned time passed as an argument to an immediately-invoked fn" do
    # The argument evaluates at the call site during compilation, so the
    # pin is frozen even though it never appears inside the fn body.
    for line <- [
          "filter (fn e -> e end).(expr(expires_at >= ^DateTime.utc_now()))",
          "filter (& &1).(expr(expires_at >= ^DateTime.utc_now()))"
        ] do
      source = """
      defmodule MyApp.Session do
        use Ash.Resource, domain: MyApp.Auth

        actions do
          read :active do
            #{line}
          end
        end
      end
      """

      assert [issue] = run_check(PinnedTimeInExpression, source)
      assert issue.trigger == "^DateTime.utc_now()"
    end
  end

  test "still reports pinned time in DSL position alongside function helpers" do
    source = """
    defmodule MyApp.Session do
      use Ash.Resource, domain: MyApp.Auth

      actions do
        read :active do
          filter expr(expires_at >= ^DateTime.utc_now())
        end
      end

      def helper, do: expr(expires_at >= ^DateTime.utc_now())
    end
    """

    assert [issue] = run_check(PinnedTimeInExpression, source)
    assert issue.line_no == 6
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

  test "flags pinned Time.utc_now with pass-the-value advice" do
    # No expression builtin returns the current time of day, so the
    # message advises an argument instead of naming a replacement.
    source = """
    defmodule MyApp.Venue do
      use Ash.Resource, domain: MyApp.Places

      actions do
        read :open_now do
          filter expr(opens_at <= ^Time.utc_now())
        end
      end
    end
    """

    assert [issue] = run_check(PinnedTimeInExpression, source)
    assert issue.trigger == "^Time.utc_now()"
    assert issue.line_no == 6
    assert issue.message =~ "never updates"
    assert issue.message =~ "action argument"
    refute issue.message =~ "Use `"
  end
end
