defmodule AshCredo.Check.Warning.WildcardAcceptOnActionTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Warning.WildcardAcceptOnAction

  test "reports issue for accept :* on create" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        create :create do
          accept :*
        end
      end
    end
    """

    assert [issue] = run_check(WildcardAcceptOnAction, source)
    assert issue.message =~ "accept :*"
    assert issue.line_no == 6
    assert issue.column != nil
  end

  test "reports issue for accept :* on update" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        update :update do
          accept :*
        end
      end
    end
    """

    assert [issue] = run_check(WildcardAcceptOnAction, source)
    assert issue.line_no == 6
    assert issue.column != nil
  end

  test "reports issue for accept :* on a soft destroy" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        destroy :archive do
          soft? true
          accept :*
        end
      end
    end
    """

    assert [issue] = run_check(WildcardAcceptOnAction, source)
    assert issue.message =~ "`archive`"
    assert issue.line_no == 7
  end

  test "reports issue for accept :* on an inline soft?: true destroy" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        destroy :archive, soft?: true, accept: :*
      end
    end
    """

    assert [issue] = run_check(WildcardAcceptOnAction, source)
    assert issue.message =~ "`archive`"
    assert issue.line_no == 5
  end

  test "no issue for accept :* on a hard destroy (Ash resets its accept)" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        destroy :purge do
          accept :*
        end
      end
    end
    """

    assert [] = run_check(WildcardAcceptOnAction, source)
  end

  test "no issue for explicit accept list" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        create :create do
          accept [:title, :body]
        end
      end
    end
    """

    assert [] = run_check(WildcardAcceptOnAction, source)
  end

  test "reports issue for wildcard writable default actions" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        defaults [create: :*, update: :*]
      end
    end
    """

    issues = run_check(WildcardAcceptOnAction, source)

    assert [_, _] = issues
    assert find_by_message(issues, "Default `create` action")
    assert find_by_message(issues, "Default `update` action")
  end

  test "reports issue for inline accept: :* on create" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        create :create, accept: :*
      end
    end
    """

    assert [issue] = run_check(WildcardAcceptOnAction, source)
    assert issue.message =~ "accept :*"
    assert issue.line_no == 5
  end

  test "reports issue for inline accept: :* on create with a do block" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        create :create, accept: :* do
          description "Create a post"
        end
      end
    end
    """

    assert [issue] = run_check(WildcardAcceptOnAction, source)
    assert issue.message =~ "accept :*"
    assert issue.line_no == 5
  end

  test "reports issue for default_accept :*" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        default_accept :*
        create :create do
          accept [:title]
        end
      end
    end
    """

    assert [issue] = run_check(WildcardAcceptOnAction, source)
    assert issue.message =~ "default_accept"
  end

  test "ignores read and destroy actions" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        read :read
        destroy :destroy
      end
    end
    """

    assert [] = run_check(WildcardAcceptOnAction, source)
  end

  test "ignores non-Ash modules" do
    source = """
    defmodule MyApp.Utils do
      def accept(:*), do: :ok
    end
    """

    assert [] = run_check(WildcardAcceptOnAction, source)
  end

  test "skips files under test directories by default" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        create :create do
          accept :*
        end
      end
    end
    """

    assert [] =
             run_check(WildcardAcceptOnAction, source,
               __filename__: "test/support/post_factory.ex"
             )
  end

  test "excluded_paths can be overridden to also scan test files" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        create :create do
          accept :*
        end
      end
    end
    """

    assert [issue] =
             run_check(WildcardAcceptOnAction, source,
               __filename__: "test/support/post_factory.ex",
               excluded_paths: []
             )

    assert issue.message =~ "accept :*"
  end

  test "a resource with no actions section yields no issues" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      attributes do
        uuid_primary_key :id
      end
    end
    """

    assert [] = run_check(WildcardAcceptOnAction, source)
  end
end
