defmodule AshCredo.Check.Warning.MissingValidationWrapperTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Warning.MissingValidationWrapper

  test "reports issue for naked validation builtin with a validate suggestion" do
    source = """
    defmodule MyApp.User do
      use Ash.Resource, domain: MyApp.Accounts

      actions do
        create :register do
          accept [:email]
          present(:email)
        end
      end
    end
    """

    assert [issue] = run_check(MissingValidationWrapper, source)
    assert issue.trigger == "present"
    assert issue.line_no == 7
    assert issue.message =~ "`validate` wrapper"
    assert issue.message =~ "validate present(...)"
  end

  test "no issue when validation builtin is wrapped in validate" do
    source = """
    defmodule MyApp.User do
      use Ash.Resource, domain: MyApp.Accounts

      actions do
        create :register do
          accept [:email]
          validate present(:email)
        end
      end
    end
    """

    assert [] = run_check(MissingValidationWrapper, source)
  end

  test "no issue when wrapped validation carries options like where:" do
    source = """
    defmodule MyApp.User do
      use Ash.Resource, domain: MyApp.Accounts

      actions do
        update :update do
          validate present(:email), where: [changing(:email)]
        end
      end
    end
    """

    assert [] = run_check(MissingValidationWrapper, source)
  end

  test "reports multiple naked validations across actions" do
    source = """
    defmodule MyApp.User do
      use Ash.Resource, domain: MyApp.Accounts

      actions do
        create :register do
          present(:email)
        end

        update :promote do
          attribute_equals(:active, true)
        end
      end
    end
    """

    issues = run_check(MissingValidationWrapper, source)
    assert [_, _] = issues
    assert find_by_trigger(issues, "present")
    assert find_by_trigger(issues, "attribute_equals").message =~ "validate attribute_equals(...)"
  end

  test "reports issue in generic action" do
    source = """
    defmodule MyApp.User do
      use Ash.Resource, domain: MyApp.Accounts

      actions do
        action :check, :ok do
          compare(:age, greater_than_or_equal_to: 18)
        end
      end
    end
    """

    assert [issue] = run_check(MissingValidationWrapper, source)
    assert issue.trigger == "compare"
  end

  test "reports naked validation builtin in read action" do
    source = """
    defmodule MyApp.User do
      use Ash.Resource, domain: MyApp.Accounts

      actions do
        read :search do
          argument :query, :string
          present(:query)
        end
      end
    end
    """

    assert [issue] = run_check(MissingValidationWrapper, source)
    assert issue.trigger == "present"
    assert issue.line_no == 7
  end

  test "no issue for wrapped validate in read action" do
    source = """
    defmodule MyApp.User do
      use Ash.Resource, domain: MyApp.Accounts

      actions do
        read :search do
          argument :query, :string
          validate present(:query)
        end
      end
    end
    """

    assert [] = run_check(MissingValidationWrapper, source)
  end

  test "reports issue for naked validation builtin in pipeline body" do
    source = """
    defmodule MyApp.User do
      use Ash.Resource, domain: MyApp.Accounts

      pipelines do
        pipeline :guarded do
          present(:email)
        end
      end
    end
    """

    assert [issue] = run_check(MissingValidationWrapper, source)
    assert issue.trigger == "present"
    assert issue.line_no == 6
  end

  test "no issue when validation builtin is wrapped inside pipeline body" do
    source = """
    defmodule MyApp.User do
      use Ash.Resource, domain: MyApp.Accounts

      pipelines do
        pipeline :guarded do
          validate present(:email)
        end
      end
    end
    """

    assert [] = run_check(MissingValidationWrapper, source)
  end

  test "does not flag naked change builtins (MissingChangeWrapper's job)" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        create :create do
          set_attribute(:status, :draft)
        end
      end
    end
    """

    assert [] = run_check(MissingValidationWrapper, source)
  end

  test "no issue when no actions section" do
    source = """
    defmodule MyApp.User do
      use Ash.Resource, domain: MyApp.Accounts

      attributes do
        uuid_primary_key :id
      end
    end
    """

    assert [] = run_check(MissingValidationWrapper, source)
  end

  test "ignores non-Ash modules" do
    source = """
    defmodule MyApp.Utils do
      def present(value), do: value != nil
    end
    """

    assert [] = run_check(MissingValidationWrapper, source)
  end
end
