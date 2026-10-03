defmodule AshCredo.Check.Readability.CalculationMissingAllowNilTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Readability.CalculationMissingAllowNil

  test "reports issue for an expression calculation without allow_nil?" do
    source = """
    defmodule MyApp.Project do
      use Ash.Resource, domain: MyApp.Work

      calculations do
        calculate :mine, :boolean, expr(author_id == ^actor(:id))
      end
    end
    """

    assert [issue] = run_check(CalculationMissingAllowNil, source)
    assert issue.message =~ "`calculate :mine` is missing an explicit `allow_nil?` option."
    assert issue.trigger == "mine"
    assert issue.line_no == 5
  end

  test "reports issue for a module calculation without allow_nil?" do
    source = """
    defmodule MyApp.Project do
      use Ash.Resource, domain: MyApp.Work

      calculations do
        calculate :summary, :string, {MyApp.Calculations.Summary, max_length: 80}
      end
    end
    """

    assert [issue] = run_check(CalculationMissingAllowNil, source)
    assert issue.message =~ ":summary"
  end

  test "reports issue when inline options omit allow_nil?" do
    source = """
    defmodule MyApp.Project do
      use Ash.Resource, domain: MyApp.Work

      calculations do
        calculate :code, :string, expr(prefix <> "-" <> suffix), public?: true
      end
    end
    """

    assert [issue] = run_check(CalculationMissingAllowNil, source)
    assert issue.message =~ ":code"
  end

  test "reports issue when the do block omits allow_nil?" do
    source = """
    defmodule MyApp.Project do
      use Ash.Resource, domain: MyApp.Work

      calculations do
        calculate :progress, :float, expr(done_count / total_count) do
          public? true
        end
      end
    end
    """

    assert [issue] = run_check(CalculationMissingAllowNil, source)
    assert issue.message =~ ":progress"
  end

  test "allow_nil? on a calculation argument does not count for the calculation" do
    source = """
    defmodule MyApp.Project do
      use Ash.Resource, domain: MyApp.Work

      calculations do
        calculate :owned_by?, :boolean, expr(owner_id == ^arg(:user_id)) do
          argument :user_id, :uuid, allow_nil?: false
        end
      end
    end
    """

    assert [issue] = run_check(CalculationMissingAllowNil, source)
    assert issue.message =~ ":owned_by?"
  end

  test "no issue when allow_nil? false is a keyword option" do
    source = """
    defmodule MyApp.Project do
      use Ash.Resource, domain: MyApp.Work

      calculations do
        calculate :progress, :float, expr(done_count / total_count), allow_nil?: false
      end
    end
    """

    assert [] = run_check(CalculationMissingAllowNil, source)
  end

  test "no issue when allow_nil? true is a keyword option" do
    source = """
    defmodule MyApp.Project do
      use Ash.Resource, domain: MyApp.Work

      calculations do
        calculate :mine, :boolean, expr(author_id == ^actor(:id)), allow_nil?: true
      end
    end
    """

    assert [] = run_check(CalculationMissingAllowNil, source)
  end

  test "no issue when allow_nil? is declared inside the do block" do
    source = """
    defmodule MyApp.Project do
      use Ash.Resource, domain: MyApp.Work

      calculations do
        calculate :progress, :float, expr(done_count / total_count) do
          allow_nil? false
        end

        calculate :mine, :boolean, expr(author_id == ^actor(:id)) do
          allow_nil? true
        end

        calculate :summary, :string do
          calculation MyApp.Calculations.Summary
          allow_nil? false
        end
      end
    end
    """

    assert [] = run_check(CalculationMissingAllowNil, source)
  end

  test "reports only the calculations without allow_nil?" do
    source = """
    defmodule MyApp.Project do
      use Ash.Resource, domain: MyApp.Work

      calculations do
        calculate :progress, :float, expr(done_count / total_count), allow_nil?: false
        calculate :mine, :boolean, expr(author_id == ^actor(:id))
        calculate :summary, :string, MyApp.Calculations.Summary
      end
    end
    """

    assert [first, second] =
             CalculationMissingAllowNil |> run_check(source) |> Enum.sort_by(& &1.line_no)

    assert first.trigger == "mine"
    assert first.line_no == 6
    assert second.trigger == "summary"
    assert second.line_no == 7
  end

  test "no issue when inline options and a do block combine and declare allow_nil?" do
    source = """
    defmodule MyApp.Project do
      use Ash.Resource, domain: MyApp.Work

      calculations do
        calculate :progress, :float, expr(done_count / total_count), allow_nil?: false do
          public? true
        end
      end
    end
    """

    assert [] = run_check(CalculationMissingAllowNil, source)
  end

  test "reports issue for a calculation named by a module attribute" do
    source = """
    defmodule MyApp.Project do
      use Ash.Resource, domain: MyApp.Work

      @name :label

      calculations do
        calculate @name, :string, expr("x")
      end
    end
    """

    assert [issue] = run_check(CalculationMissingAllowNil, source)
    assert issue.message =~ "`calculate @name`"
    assert issue.trigger == "@name"
  end

  test "ignores aggregates next to calculations" do
    source = """
    defmodule MyApp.Project do
      use Ash.Resource, domain: MyApp.Work

      aggregates do
        count :task_count, :tasks, allow_nil?: false
        max :latest_due_at, :tasks, :due_at
      end

      calculations do
        calculate :task_count, :integer, expr(task_count)
      end
    end
    """

    assert [issue] = run_check(CalculationMissingAllowNil, source)
    assert issue.line_no == 10
  end

  test "reports a calculation whose implementation is a module attribute" do
    source = """
    defmodule MyApp.Project do
      use Ash.Resource, domain: MyApp.Work

      @calculation {MyApp.Calculations.Label, []}

      calculations do
        calculate :label, :string, @calculation
      end
    end
    """

    assert [issue] = run_check(CalculationMissingAllowNil, source)
    assert issue.message =~ "`calculate :label`"
  end

  test "reports issue in a resource fragment" do
    source = """
    defmodule MyApp.Project.Calculations do
      use Spark.Dsl.Fragment, of: Ash.Resource

      calculations do
        calculate :label, :string, expr("x")
      end
    end
    """

    assert [issue] = run_check(CalculationMissingAllowNil, source)
    assert issue.message =~ "`calculate :label`"
    assert issue.line_no == 5
  end

  test "ignores fragments of other DSLs" do
    source = """
    defmodule MyApp.Work.Calculations do
      use Spark.Dsl.Fragment, of: Ash.Domain

      calculations do
        calculate :label, :string, expr("x")
      end
    end
    """

    assert [] = run_check(CalculationMissingAllowNil, source)
  end

  test "no issue when no calculations section" do
    source = """
    defmodule MyApp.Project do
      use Ash.Resource, domain: MyApp.Work

      attributes do
        uuid_primary_key :id
      end
    end
    """

    assert [] = run_check(CalculationMissingAllowNil, source)
  end

  test "ignores non-Ash modules" do
    source = """
    defmodule MyApp.Utils do
      def calculate(name, type, expr), do: {name, type, expr}
    end
    """

    assert [] = run_check(CalculationMissingAllowNil, source)
  end
end
