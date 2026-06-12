defmodule AshCredo.Check.Warning.CompileTimeDefaultTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Warning.CompileTimeDefault

  test "reports frozen DateTime.utc_now() in an inline attribute default" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      attributes do
        uuid_primary_key :id
        attribute :scheduled_at, :utc_datetime, default: DateTime.utc_now()
      end
    end
    """

    assert [issue] = run_check(CompileTimeDefault, source)
    assert issue.trigger == "DateTime.utc_now()"
    assert issue.line_no == 6
    assert issue.message =~ "compile time"
    assert issue.message =~ "&DateTime.utc_now/0"
  end

  test "reports frozen default in an attribute do-block" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      attributes do
        attribute :published_on, :date do
          default Date.utc_today()
        end
      end
    end
    """

    assert [issue] = run_check(CompileTimeDefault, source)
    assert issue.trigger == "Date.utc_today()"
    assert issue.line_no == 6
  end

  test "reports frozen update_default" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      attributes do
        attribute :updated_at, :utc_datetime, update_default: DateTime.utc_now()
      end
    end
    """

    assert [issue] = run_check(CompileTimeDefault, source)
    assert issue.message =~ "`update_default`"
    assert issue.message =~ "update_default: &DateTime.utc_now/0"
  end

  test "reports frozen Ash.UUID.generate() default" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      attributes do
        attribute :token, :uuid, default: Ash.UUID.generate()
      end
    end
    """

    assert [issue] = run_check(CompileTimeDefault, source)
    assert issue.trigger == "Ash.UUID.generate()"
  end

  test "reports frozen default on an action argument" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        read :recent do
          argument :since, :utc_datetime, default: DateTime.utc_now()
        end
      end
    end
    """

    assert [issue] = run_check(CompileTimeDefault, source)
    assert issue.trigger == "DateTime.utc_now()"
    assert issue.line_no == 6
  end

  test "reports frozen default on a calculation argument" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      calculations do
        calculate :age_at, :integer, expr(date_diff(^arg(:as_of), birthdate)) do
          argument :as_of, :date, default: Date.utc_today()
        end
      end
    end
    """

    assert [issue] = run_check(CompileTimeDefault, source)
    assert issue.trigger == "Date.utc_today()"
  end

  test "reports frozen call nested inside a container default" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      attributes do
        attribute :meta, :map, default: %{generated_at: DateTime.utc_now()}
      end
    end
    """

    assert [issue] = run_check(CompileTimeDefault, source)
    assert issue.trigger == "DateTime.utc_now()"
  end

  test "reports frozen call with arguments" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      attributes do
        attribute :scheduled_at, :utc_datetime, default: DateTime.utc_now(:second)
      end
    end
    """

    assert [issue] = run_check(CompileTimeDefault, source)
    assert issue.trigger == "DateTime.utc_now()"
  end

  test "no issue for zero-arity captures" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      attributes do
        uuid_primary_key :id
        attribute :scheduled_at, :utc_datetime, default: &DateTime.utc_now/0
        attribute :token, :uuid, default: &Ash.UUID.generate/0

        attribute :updated_at, :utc_datetime do
          update_default &DateTime.utc_now/0
        end
      end
    end
    """

    assert [] = run_check(CompileTimeDefault, source)
  end

  test "no issue for anonymous function defaults" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      attributes do
        attribute :scheduled_at, :utc_datetime, default: fn -> DateTime.utc_now(:second) end
      end
    end
    """

    assert [] = run_check(CompileTimeDefault, source)
  end

  test "no issue for literal and unrelated defaults" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      attributes do
        attribute :status, :atom, default: :draft
        attribute :count, :integer, default: 0
        attribute :config, :map, default: %{}
        attribute :label, :string, default: String.duplicate("-", 3)
      end

      actions do
        read :recent do
          argument :limit, :integer, default: 10
        end
      end
    end
    """

    assert [] = run_check(CompileTimeDefault, source)
  end

  test "no issue for timestamps builtins" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      attributes do
        uuid_primary_key :id
        create_timestamp :inserted_at
        update_timestamp :updated_at
      end
    end
    """

    assert [] = run_check(CompileTimeDefault, source)
  end

  test "ignores non-Ash modules" do
    source = """
    defmodule MyApp.Config do
      def base, do: [default: DateTime.utc_now()]
    end
    """

    assert [] = run_check(CompileTimeDefault, source)
  end
end
