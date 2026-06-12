defmodule AshCredo.Check.Warning.MissingBuiltinWrapperTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Warning.MissingBuiltinWrapper

  describe "change builtins" do
    test "reports naked manage_relationship in create action" do
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

      assert [issue] = run_check(MissingBuiltinWrapper, source)
      assert issue.trigger == "manage_relationship"
      assert issue.message =~ "`change` wrapper"
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

      assert [] = run_check(MissingBuiltinWrapper, source)
    end

    test "reports naked set_attribute in update and destroy actions" do
      source = """
      defmodule MyApp.Post do
        use Ash.Resource, domain: MyApp.Blog

        actions do
          update :publish do
            set_attribute(:published, true)
          end

          destroy :archive do
            set_attribute(:archived, true)
          end
        end
      end
      """

      issues = run_check(MissingBuiltinWrapper, source)
      assert [_, _] = issues
      assert Enum.all?(issues, &(&1.trigger == "set_attribute"))
    end

    test "reports multiple naked builtins of mixed families in one action" do
      source = """
      defmodule MyApp.Post do
        use Ash.Resource, domain: MyApp.Blog

        actions do
          create :create_with_tags do
            argument :tags, {:array, :map}
            set_attribute(:status, :draft)
            manage_relationship(:tags, :tags, type: :create)
            present(:title)
          end
        end
      end
      """

      issues = run_check(MissingBuiltinWrapper, source)
      assert [_, _, _] = issues

      assert MapSet.equal?(
               trigger_set(issues),
               MapSet.new(~w(set_attribute manage_relationship present))
             )

      assert find_by_trigger(issues, "present").message =~ "`validate` wrapper"
      assert find_by_trigger(issues, "set_attribute").message =~ "`change` wrapper"
    end

    test "does not flag change builtins in read or generic actions (they do not compile there)" do
      source = """
      defmodule MyApp.Post do
        use Ash.Resource, domain: MyApp.Blog

        actions do
          read :search do
            set_attribute(:foo, 1)
          end

          action :promote do
            set_attribute(:featured, true)
          end
        end
      end
      """

      assert [] = run_check(MissingBuiltinWrapper, source)
    end

    test "no issue for non-builtin calls in action body" do
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

      assert [] = run_check(MissingBuiltinWrapper, source)
    end
  end

  describe "validation builtins" do
    test "reports naked present with trigger, line, and validate suggestion" do
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

      assert [issue] = run_check(MissingBuiltinWrapper, source)
      assert issue.trigger == "present"
      assert issue.line_no == 7
      assert issue.message =~ "`validate` wrapper"
      assert issue.message =~ "validate present(...)"
    end

    test "no issue when validation builtin is wrapped, including with options" do
      source = """
      defmodule MyApp.User do
        use Ash.Resource, domain: MyApp.Accounts

        actions do
          create :register do
            accept [:email]
            validate present(:email)
          end

          update :update do
            validate present(:email), where: [changing(:email)]
          end
        end
      end
      """

      assert [] = run_check(MissingBuiltinWrapper, source)
    end

    test "reports naked validations in read and generic actions" do
      source = """
      defmodule MyApp.User do
        use Ash.Resource, domain: MyApp.Accounts

        actions do
          read :search do
            argument :query, :string
            present(:query)
          end

          action :check, :ok do
            compare(:age, greater_than_or_equal_to: 18)
          end
        end
      end
      """

      issues = run_check(MissingBuiltinWrapper, source)
      assert [_, _] = issues
      assert find_by_trigger(issues, "present")
      assert find_by_trigger(issues, "compare").message =~ "validate compare(...)"
    end
  end

  describe "preparation builtins" do
    test "reports naked build in read action with prepare suggestion" do
      source = """
      defmodule MyApp.Post do
        use Ash.Resource, domain: MyApp.Blog

        actions do
          read :recent do
            build(sort: [inserted_at: :desc])
          end
        end
      end
      """

      assert [issue] = run_check(MissingBuiltinWrapper, source)
      assert issue.trigger == "build"
      assert issue.line_no == 6
      assert issue.message =~ "`prepare` wrapper"
    end

    test "no issue when build is wrapped in prepare" do
      source = """
      defmodule MyApp.Post do
        use Ash.Resource, domain: MyApp.Blog

        actions do
          read :recent do
            prepare build(sort: [inserted_at: :desc])
          end
        end
      end
      """

      assert [] = run_check(MissingBuiltinWrapper, source)
    end

    test "set_context in read and generic actions gets prepare advice" do
      source = """
      defmodule MyApp.Post do
        use Ash.Resource, domain: MyApp.Blog

        actions do
          read :search do
            set_context(%{tracing: true})
          end

          action :compute, :integer do
            set_context(%{a: 1})
            run fn _input, _context -> {:ok, 1} end
          end
        end
      end
      """

      issues = run_check(MissingBuiltinWrapper, source)
      assert [_, _] = issues
      assert Enum.all?(issues, &(&1.trigger == "set_context"))
      assert Enum.all?(issues, &(&1.message =~ "`prepare` wrapper"))
    end

    test "set_context in create/update/destroy gets change advice" do
      source = """
      defmodule MyApp.Post do
        use Ash.Resource, domain: MyApp.Blog

        actions do
          destroy :archive do
            set_context(%{audit: true})
          end
        end
      end
      """

      assert [issue] = run_check(MissingBuiltinWrapper, source)
      assert issue.trigger == "set_context"
      assert issue.message =~ "`change` wrapper"
    end

    test "does not flag build in create/update/destroy actions (it does not compile there)" do
      source = """
      defmodule MyApp.Post do
        use Ash.Resource, domain: MyApp.Blog

        actions do
          create :make do
            build(sort: [:id])
          end

          update :rename do
            build(sort: [:id])
          end
        end
      end
      """

      assert [] = run_check(MissingBuiltinWrapper, source)
    end
  end

  describe "pipeline bodies" do
    test "reports naked builtins of all three families with family-correct advice" do
      source = """
      defmodule MyApp.Post do
        use Ash.Resource, domain: MyApp.Blog

        pipelines do
          pipeline :scoring do
            set_attribute(:score, 0)
            present(:score)
            build(sort: [:score])
          end
        end
      end
      """

      issues = run_check(MissingBuiltinWrapper, source)
      assert [_, _, _] = issues
      assert find_by_trigger(issues, "set_attribute").message =~ "`change` wrapper"
      assert find_by_trigger(issues, "present").message =~ "`validate` wrapper"
      assert find_by_trigger(issues, "build").message =~ "`prepare` wrapper"
    end

    test "set_context in a pipeline gets change advice and is flagged exactly once" do
      source = """
      defmodule MyApp.Post do
        use Ash.Resource, domain: MyApp.Blog

        pipelines do
          pipeline :ctx do
            set_context(%{tracing: true})
          end
        end
      end
      """

      assert [issue] = run_check(MissingBuiltinWrapper, source)
      assert issue.trigger == "set_context"
      assert issue.message =~ "`change` wrapper"
    end

    test "no issue when pipeline builtins are wrapped" do
      source = """
      defmodule MyApp.Post do
        use Ash.Resource, domain: MyApp.Blog

        pipelines do
          pipeline :scoring do
            change set_attribute(:score, 0)
            validate present(:score)
            prepare build(sort: [:score])
          end
        end
      end
      """

      assert [] = run_check(MissingBuiltinWrapper, source)
    end
  end

  test "no issue when no actions or pipelines section" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      attributes do
        uuid_primary_key :id
      end
    end
    """

    assert [] = run_check(MissingBuiltinWrapper, source)
  end

  test "ignores non-Ash modules" do
    source = """
    defmodule MyApp.Utils do
      def set_attribute(key, value), do: {key, value}
      def present(value), do: value != nil
      def build(opts), do: opts
    end
    """

    assert [] = run_check(MissingBuiltinWrapper, source)
  end
end
