defmodule AshCredo.Check.Warning.RedundantValidationTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Warning.RedundantValidation
  alias AshCredo.Introspection.Compiled, as: CompiledIntrospection

  # Tests resolve attributes against the compiled fixture
  # `AshCredoFixtures.Blog.Contact` (test/support/fixtures/ash_fixtures.ex):
  # `:name` and `:handle` have `allow_nil? false`, `:nickname` is nullable,
  # and the `:import` create action lists `:name` in `allow_nil_input` -
  # which also shields GLOBAL validations on `:name`, so the global-scope
  # happy-path tests use `:handle`.

  setup do
    CompiledIntrospection.clear_cache()
    :ok
  end

  test "reports redundant present on a non-nullable attribute in a create action" do
    source = """
    defmodule AshCredoFixtures.Blog.Contact do
      use Ash.Resource, domain: AshCredoFixtures.Blog

      actions do
        create :create do
          validate present(:name)
        end
      end
    end
    """

    assert [issue] = run_check(RedundantValidation, source)
    assert issue.trigger == "present"
    assert issue.line_no == 6
    assert issue.message =~ "allow_nil? false"
    assert issue.message =~ ":name"
  end

  test "reports redundant present in an update action" do
    source = """
    defmodule AshCredoFixtures.Blog.Contact do
      use Ash.Resource, domain: AshCredoFixtures.Blog

      actions do
        update :rename do
          validate present(:name)
        end
      end
    end
    """

    assert [issue] = run_check(RedundantValidation, source)
    assert issue.trigger == "present"
  end

  test "reports redundant present in the global validations section" do
    source = """
    defmodule AshCredoFixtures.Blog.Contact do
      use Ash.Resource, domain: AshCredoFixtures.Blog

      validations do
        validate present(:handle)
      end
    end
    """

    assert [issue] = run_check(RedundantValidation, source)
    assert issue.line_no == 5
  end

  test "reports redundant present declared with a do-block message" do
    source = """
    defmodule AshCredoFixtures.Blog.Contact do
      use Ash.Resource, domain: AshCredoFixtures.Blog

      validations do
        validate present(:handle) do
          message "Handle is required"
        end
      end
    end
    """

    assert [issue] = run_check(RedundantValidation, source)
    assert issue.trigger == "present"
  end

  test "reports redundant present with at_least up to the field count" do
    source = """
    defmodule AshCredoFixtures.Blog.Contact do
      use Ash.Resource, domain: AshCredoFixtures.Blog

      actions do
        create :create do
          validate present(:name, at_least: 1)
        end
      end
    end
    """

    assert [issue] = run_check(RedundantValidation, source)
    assert issue.trigger == "present"
  end

  test "no issue for present on a nullable attribute" do
    source = """
    defmodule AshCredoFixtures.Blog.Contact do
      use Ash.Resource, domain: AshCredoFixtures.Blog

      actions do
        create :create do
          validate present(:nickname)
        end
      end
    end
    """

    assert [] = run_check(RedundantValidation, source)
  end

  test "no issue when any referenced field is nullable" do
    source = """
    defmodule AshCredoFixtures.Blog.Contact do
      use Ash.Resource, domain: AshCredoFixtures.Blog

      actions do
        create :create do
          validate present([:name, :nickname])
        end
      end
    end
    """

    assert [] = run_check(RedundantValidation, source)
  end

  test "no issue when the action opens the attribute via allow_nil_input" do
    source = """
    defmodule AshCredoFixtures.Blog.Contact do
      use Ash.Resource, domain: AshCredoFixtures.Blog

      actions do
        create :import do
          validate present(:name)
        end
      end
    end
    """

    assert [] = run_check(RedundantValidation, source)
  end

  test "no issue for a global validation when any action allows nil input for the field" do
    source = """
    defmodule AshCredoFixtures.Blog.Contact do
      use Ash.Resource, domain: AshCredoFixtures.Blog

      validations do
        validate present(:name), on: [:create]
      end
    end
    """

    # The compiled :import action lists :name in allow_nil_input, so the
    # global validation is load-bearing for that action.
    assert [] = run_check(RedundantValidation, source)
  end

  test "no issue when an update action defines a same-named argument" do
    # The compiled :reslug action defines `argument :slug`, so `present`
    # validates the argument, not the attribute, in the atomic path
    # (Ash.Resource.Validation.Present.atomic/3) - a real constraint
    # despite the attribute's allow_nil? false.
    source = """
    defmodule AshCredoFixtures.Blog.Contact do
      use Ash.Resource, domain: AshCredoFixtures.Blog

      actions do
        update :reslug do
          validate present(:slug)
        end
      end
    end
    """

    assert [] = run_check(RedundantValidation, source)
  end

  test "reports present when a create action defines a same-named argument" do
    # Creates never execute atomically, so the non-atomic fallback to the
    # attribute always applies and the validation stays redundant - the
    # argument escape must not fire for create actions.
    source = """
    defmodule AshCredoFixtures.Blog.Contact do
      use Ash.Resource, domain: AshCredoFixtures.Blog

      actions do
        create :import_slugged do
          validate present(:slug)
        end
      end
    end
    """

    assert [issue] = run_check(RedundantValidation, source)
    assert issue.message =~ ":slug"
  end

  test "reports present on the same attribute in an action without the argument" do
    source = """
    defmodule AshCredoFixtures.Blog.Contact do
      use Ash.Resource, domain: AshCredoFixtures.Blog

      actions do
        update :rename do
          validate present(:slug)
        end
      end
    end
    """

    assert [issue] = run_check(RedundantValidation, source)
    assert issue.message =~ ":slug"
  end

  test "no issue for a global validation when an update action defines a same-named argument" do
    source = """
    defmodule AshCredoFixtures.Blog.Contact do
      use Ash.Resource, domain: AshCredoFixtures.Blog

      validations do
        validate present(:slug)
      end
    end
    """

    # The compiled :reslug update action defines `argument :slug`, so the
    # global validation is load-bearing for that action's atomic path.
    # (The create :import_slugged argument alone would not suppress it.)
    assert [] = run_check(RedundantValidation, source)
  end

  test "no issue for present in read actions (checks arguments, not attributes)" do
    source = """
    defmodule AshCredoFixtures.Blog.Contact do
      use Ash.Resource, domain: AshCredoFixtures.Blog

      actions do
        read :search do
          argument :name, :string
          validate present(:name)
        end
      end
    end
    """

    assert [] = run_check(RedundantValidation, source)
  end

  test "no issue for a global validation targeting read actions" do
    source = """
    defmodule AshCredoFixtures.Blog.Contact do
      use Ash.Resource, domain: AshCredoFixtures.Blog

      validations do
        validate present(:handle), on: [:read]
      end
    end
    """

    assert [] = run_check(RedundantValidation, source)
  end

  test "no issue for present with exactly or at_most semantics" do
    source = """
    defmodule AshCredoFixtures.Blog.Contact do
      use Ash.Resource, domain: AshCredoFixtures.Blog

      actions do
        create :create do
          validate present(:name, exactly: 0)
          validate present(:name, at_most: 1)
        end
      end
    end
    """

    assert [] = run_check(RedundantValidation, source)
  end

  test "no issue for non-literal fields" do
    source = """
    defmodule AshCredoFixtures.Blog.Contact do
      use Ash.Resource, domain: AshCredoFixtures.Blog

      actions do
        create :create do
          validate present(@required_field)
        end
      end
    end
    """

    assert [] = run_check(RedundantValidation, source)
  end

  test "no issue when the source names an action the compiled module lacks" do
    source = """
    defmodule AshCredoFixtures.Blog.Contact do
      use Ash.Resource, domain: AshCredoFixtures.Blog

      actions do
        create :not_compiled do
          validate present(:name)
        end
      end
    end
    """

    assert [] = run_check(RedundantValidation, source)
  end

  test "reports the not-loadable diagnostic for unknown resource modules" do
    source = """
    defmodule MyApp.NotCompiled do
      use Ash.Resource, domain: MyApp.Domain

      actions do
        create :create do
          validate present(:name)
        end
      end
    end
    """

    assert [issue] = run_check(RedundantValidation, source)
    assert issue.message =~ "Could not load"
  end

  test "ignores non-Ash modules" do
    source = """
    defmodule MyApp.Utils do
      def validate(x), do: present(x)
      def present(x), do: x != nil
    end
    """

    assert [] = run_check(RedundantValidation, source)
  end
end
