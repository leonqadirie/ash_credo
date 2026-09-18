defmodule AshCredo.Check.Refactor.AnonymousFunctionInDslTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Refactor.AnonymousFunctionInDsl

  test "reports fn passed to change in a create action" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        create :create do
          change fn changeset, _context -> changeset end
        end
      end
    end
    """

    assert [issue] = run_check(AnonymousFunctionInDsl, source)
    assert issue.trigger == "change"
    assert issue.line_no == 6
    assert issue.message =~ "atomic"
    assert issue.message =~ "Ash.Resource.Change"
  end

  test "reports fn passed to validate in an update action" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        update :update do
          validate fn changeset, _context -> :ok end
        end
      end
    end
    """

    assert [issue] = run_check(AnonymousFunctionInDsl, source)
    assert issue.trigger == "validate"
    assert issue.message =~ "Ash.Resource.Validation"
  end

  test "reports fn passed to prepare in a read action" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        read :search do
          prepare fn query, _context -> query end
        end
      end
    end
    """

    assert [issue] = run_check(AnonymousFunctionInDsl, source)
    assert issue.trigger == "prepare"
    assert issue.message =~ "Ash.Resource.Preparation"
    refute issue.message =~ "atomic"
  end

  test "reports function captures the same as fn" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        create :create do
          change &MyApp.Helpers.slugify/2
        end
      end
    end
    """

    assert [issue] = run_check(AnonymousFunctionInDsl, source)
    assert issue.trigger == "change"
  end

  test "reports anonymous functions in the global changes/validations/preparations sections" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      changes do
        change fn changeset, _context -> changeset end
      end

      validations do
        validate fn changeset, _context -> :ok end
      end

      preparations do
        prepare fn query, _context -> query end
      end
    end
    """

    issues = run_check(AnonymousFunctionInDsl, source)
    assert [_, _, _] = issues
    assert MapSet.equal?(trigger_set(issues), MapSet.new(~w(change validate prepare)))
    assert sorted_lines(issues) == [5, 9, 13]
  end

  test "reports anonymous functions inside pipeline bodies" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      pipelines do
        pipeline :slugify do
          change fn changeset, _context -> changeset end
        end
      end
    end
    """

    assert [issue] = run_check(AnonymousFunctionInDsl, source)
    assert issue.trigger == "change"
    assert issue.line_no == 6
  end

  test "no issue for module-based callbacks" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        create :create do
          change MyApp.Changes.SlugifyName
          validate {MyApp.Validations.NameNotProfane, []}
        end

        read :search do
          prepare MyApp.Preparations.DefaultSort
        end
      end
    end
    """

    assert [] = run_check(AnonymousFunctionInDsl, source)
  end

  test "no issue for wrapped builtins" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        create :create do
          change set_attribute(:status, :draft)
          validate present(:name)
        end

        read :search do
          prepare build(sort: [:name])
        end
      end
    end
    """

    assert [] = run_check(AnonymousFunctionInDsl, source)
  end

  test "reports fn passed to calculate" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      calculations do
        calculate :display_name, :string, fn records, _context ->
          Enum.map(records, & &1.name)
        end
      end
    end
    """

    assert [issue] = run_check(AnonymousFunctionInDsl, source)
    assert issue.trigger == "calculate"
    assert issue.line_no == 5
    assert issue.message =~ "expression"
    assert issue.message =~ "Ash.Resource.Calculation"
  end

  test "reports fn given via the calculation option in a calculate do-block" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      calculations do
        calculate :display_name, :string do
          calculation fn records, _context -> Enum.map(records, & &1.name) end
        end
      end
    end
    """

    assert [issue] = run_check(AnonymousFunctionInDsl, source)
    assert issue.trigger == "calculate"
    assert issue.line_no == 6
  end

  test "no issue for expr, module, and tuple calculations" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      calculations do
        calculate :full_name, :string, expr(first_name <> " " <> last_name)
        calculate :slug, :string, MyApp.Calculations.Slug
        calculate :initials, :string, {MyApp.Calculations.Initials, separator: "."}

        calculate :display, :string, MyApp.Calculations.Display do
          public? true
        end
      end
    end
    """

    assert [] = run_check(AnonymousFunctionInDsl, source)
  end

  test "no issue for anonymous functions in regular resource functions" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        create :create
      end

      def transform(items) do
        Enum.map(items, fn item -> item.name end)
      end
    end
    """

    assert [] = run_check(AnonymousFunctionInDsl, source)
  end

  test "ignores non-Ash modules" do
    source = """
    defmodule MyApp.Pipeline do
      def run do
        change fn x -> x end
        validate fn x -> x end
      end

      def change(fun), do: fun
      def validate(fun), do: fun
    end
    """

    assert [] = run_check(AnonymousFunctionInDsl, source)
  end

  test "reports fn passed to run in a generic action" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        action :published?, :boolean do
          run fn input, _context -> {:ok, true} end
        end
      end
    end
    """

    assert [issue] = run_check(AnonymousFunctionInDsl, source)
    assert issue.trigger == "run"
    assert issue.line_no == 6
    assert issue.message =~ "Ash.Resource.Actions.Implementation"
  end

  test "no issue for a module or tuple run" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        action :published?, :boolean do
          run MyApp.Posts.Published
        end

        action :counted, :integer do
          run {MyApp.Posts.Counted, scope: :all}
        end
      end
    end
    """

    assert [] = run_check(AnonymousFunctionInDsl, source)
  end

  test "reports anonymous functions passed to a pub_sub transform" do
    source = """
    defmodule MyApp.Message do
      use Ash.Resource, domain: MyApp.Chat

      pub_sub do
        module MyAppWeb.Endpoint

        publish :create, ["messages", :conversation_id] do
          transform fn %{data: message} -> %{id: message.id} end
        end

        publish_all :update, ["conversations", :user_id] do
          transform & &1.data
        end
      end
    end
    """

    issues = run_check(AnonymousFunctionInDsl, source)
    assert [_, _] = issues
    assert MapSet.equal?(trigger_set(issues), MapSet.new(["transform"]))
    assert sorted_lines(issues) == [8, 12]
    assert Enum.all?(issues, &(&1.message =~ "Spark lifts it"))
  end

  test "no issue for a remote capture outside the wrapped options" do
    source = """
    defmodule MyApp.Message do
      use Ash.Resource, domain: MyApp.Chat

      pub_sub do
        module MyAppWeb.Endpoint

        publish :create, ["messages", :conversation_id] do
          transform &MyApp.Chat.Notification.message/1
        end
      end
    end
    """

    assert [] = run_check(AnonymousFunctionInDsl, source)
  end

  test "reports a local capture outside the wrapped options, which Spark still lifts" do
    source = """
    defmodule MyApp.Message do
      use Ash.Resource, domain: MyApp.Chat

      pub_sub do
        module MyAppWeb.Endpoint

        publish :create, ["messages", :conversation_id] do
          transform &payload/1
        end
      end

      def payload(notification), do: notification.data
    end
    """

    assert [issue] = run_check(AnonymousFunctionInDsl, source)
    assert issue.trigger == "transform"
    assert issue.line_no == 8
  end

  test "reports anonymous functions in an extension's nested options" do
    source = """
    defmodule MyApp.User do
      use Ash.Resource, domain: MyApp.Accounts

      authentication do
        strategies do
          google do
            client_id fn _, _ -> {:ok, "id"} end
            client_secret MyApp.Secrets
          end
        end
      end
    end
    """

    assert [issue] = run_check(AnonymousFunctionInDsl, source)
    assert issue.trigger == "client_id"
    assert issue.line_no == 7
    assert issue.message =~ "Spark lifts it"
  end

  test "no issue for anonymous functions inside a module nested in the resource" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      defmodule Status do
        use Ash.Type.Enum, values: [:draft, :published]

        def labels(values), do: Enum.map(values, fn value -> to_string(value) end)
      end

      actions do
        create :create
      end
    end
    """

    assert [] = run_check(AnonymousFunctionInDsl, source)
  end

  test "no issue for anonymous functions inside a quote or a module attribute" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      @default_slug fn title -> String.downcase(title) end

      defmacro derive_slug do
        quote do
          def slug(title), do: Enum.map([title], fn part -> part end)
        end
      end

      actions do
        create :create
      end
    end
    """

    assert [] = run_check(AnonymousFunctionInDsl, source)
  end
end
