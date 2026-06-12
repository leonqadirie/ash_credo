defmodule AshCredo.Check.Warning.MissingChangeWrapperTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Warning.MissingChangeWrapper

  test "reports issue for naked manage_relationship in create action" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        create :some_action do
          argument :thing, :map
          manage_relationship(:thing, :thing, type: :create)
        end
      end
    end
    """

    assert [issue] = run_check(MissingChangeWrapper, source)
    assert issue.message =~ "manage_relationship"
    assert issue.message =~ "change"
  end

  test "no issue when manage_relationship is wrapped in change" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        create :some_action do
          argument :thing, :map
          change manage_relationship(:thing, :thing, type: :create)
        end
      end
    end
    """

    assert [] = run_check(MissingChangeWrapper, source)
  end

  test "reports issue for naked set_attribute in update action" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        update :publish do
          set_attribute(:published, true)
        end
      end
    end
    """

    assert [issue] = run_check(MissingChangeWrapper, source)
    assert issue.message =~ "set_attribute"
  end

  test "no issue when set_attribute is wrapped in change" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        update :publish do
          change set_attribute(:published, true)
        end
      end
    end
    """

    assert [] = run_check(MissingChangeWrapper, source)
  end

  test "reports issue for naked relate_actor in create action" do
    source = """
    defmodule MyApp.Comment do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        create :post_comment do
          relate_actor(:author)
        end
      end
    end
    """

    assert [issue] = run_check(MissingChangeWrapper, source)
    assert issue.message =~ "relate_actor"
  end

  test "reports multiple naked changes in one action" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        create :create_with_tags do
          argument :tags, {:array, :map}
          set_attribute(:status, :draft)
          manage_relationship(:tags, :tags, type: :create)
        end
      end
    end
    """

    issues = run_check(MissingChangeWrapper, source)
    assert [_, _] = issues
    triggers = Enum.map(issues, & &1.trigger)
    assert "set_attribute" in triggers
    assert "manage_relationship" in triggers
  end

  test "reports issue in destroy action" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        destroy :archive do
          set_attribute(:archived, true)
        end
      end
    end
    """

    assert [issue] = run_check(MissingChangeWrapper, source)
    assert issue.message =~ "set_attribute"
  end

  test "reports issue in generic action" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        action :promote do
          set_attribute(:featured, true)
        end
      end
    end
    """

    assert [issue] = run_check(MissingChangeWrapper, source)
    assert issue.message =~ "set_attribute"
  end

  test "no issue for non-change calls in action body" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        create :create do
          argument :title, :string
          accept [:title, :body]
          change set_attribute(:status, :draft)
        end
      end
    end
    """

    assert [] = run_check(MissingChangeWrapper, source)
  end

  test "does not scan read actions (change builtins do not compile there)" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        read :search do
          set_attribute(:foo, 1)
        end
      end
    end
    """

    assert [] = run_check(MissingChangeWrapper, source)
  end

  test "does not flag naked validation builtins (MissingValidationWrapper's job)" do
    source = """
    defmodule MyApp.User do
      use Ash.Resource, domain: MyApp.Accounts

      actions do
        create :register do
          present(:email)
        end
      end
    end
    """

    assert [] = run_check(MissingChangeWrapper, source)
  end

  test "no issue when no actions section" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      attributes do
        uuid_primary_key :id
      end
    end
    """

    assert [] = run_check(MissingChangeWrapper, source)
  end

  test "ignores non-Ash modules" do
    source = """
    defmodule MyApp.Utils do
      def set_attribute(key, value), do: {key, value}
    end
    """

    assert [] = run_check(MissingChangeWrapper, source)
  end
end
