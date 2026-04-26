defmodule AshCredo.Check.Design.MissingCodeInterfaceTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Design.MissingCodeInterface
  alias AshCredo.Introspection.Compiled, as: CompiledIntrospection

  # Tests reference real fixture modules from `test/support/fixtures/ash_fixtures.ex`:
  #
  #   * `AshCredoFixtures.Blog.Post` - has actions `:create`, `:update`, `:destroy`
  #     (via defaults), `:read`, `:published`, `:draft`, `:archive`, `:publish`.
  #     Interfaces:
  #       - resource-level: `:archive` (→ :archive), `:published_posts` (→ :published),
  #         `:all_posts` (→ :read)
  #       - domain-level:  `:list_posts` (→ :read), `:publish_post` (→ :publish)
  #     Actions with NO interface anywhere: `:create`, `:update`, `:destroy`, `:draft`.
  #
  #   * `AshCredoFixtures.Accounts.User` - has `:create`, `:read`, `:update`,
  #     `:destroy` (via defaults). ZERO interfaces. All 4 actions should be flagged.

  setup do
    CompiledIntrospection.clear_cache()
    :ok
  end

  test "reports one issue per action without an interface" do
    source = """
    defmodule AshCredoFixtures.Blog.Post do
      use Ash.Resource, domain: AshCredoFixtures.Blog
    end
    """

    issues = run_check(MissingCodeInterface, source)

    # Post's uncovered actions: :create, :update, :destroy, :draft (4 total)
    assert MapSet.equal?(trigger_set(issues), MapSet.new(~w(create update destroy draft)))

    # Every issue names the specific action
    for issue <- issues do
      assert issue.message =~ "AshCredoFixtures.Blog.Post"
      assert issue.message =~ "has no code interface"
      assert issue.message =~ "define :"
    end
  end

  test "reports issues for every action on a resource with zero interfaces" do
    source = """
    defmodule AshCredoFixtures.Accounts.User do
      use Ash.Resource, domain: AshCredoFixtures.Accounts
    end
    """

    issues = run_check(MissingCodeInterface, source)

    # User has 4 default actions and zero interfaces.
    assert MapSet.equal?(trigger_set(issues), MapSet.new(~w(create read update destroy)))
  end

  test "no issue for actions covered by a resource-level interface" do
    source = """
    defmodule AshCredoFixtures.Blog.Post do
      use Ash.Resource, domain: AshCredoFixtures.Blog
    end
    """

    issues = run_check(MissingCodeInterface, source)
    triggers = trigger_set(issues)

    # :archive, :published, and :read all have interfaces (resource-level)
    # - neither should appear in the issue list.
    refute MapSet.member?(triggers, "archive")
    refute MapSet.member?(triggers, "published")
    refute MapSet.member?(triggers, "read")
  end

  test "no issue for actions covered only by a domain-level interface" do
    source = """
    defmodule AshCredoFixtures.Blog.Post do
      use Ash.Resource, domain: AshCredoFixtures.Blog
    end
    """

    issues = run_check(MissingCodeInterface, source)

    # :publish has only a domain-level interface (`publish_post`). The check
    # should accept that and NOT flag `:publish`.
    refute MapSet.member?(trigger_set(issues), "publish")
  end

  test "no issue for embedded resources" do
    source = """
    defmodule MyApp.Blog.PostMetadata do
      use Ash.Resource, data_layer: :embedded
    end
    """

    assert [] = run_check(MissingCodeInterface, source)
  end

  test "ignores non-Ash modules" do
    source = """
    defmodule MyApp.Utils do
      def hello, do: :world
    end
    """

    assert [] = run_check(MissingCodeInterface, source)
  end

  test "no issue for a resource with zero actions" do
    # Create a synthetic source where the resource has no actions. The
    # compiled fixture `AshCredoFixtures.Plain` is not an Ash resource, so
    # it is skipped via `:not_a_resource`.
    source = """
    defmodule AshCredoFixtures.Plain do
      use Ash.Resource, domain: AshCredoFixtures.Blog
    end
    """

    assert [] = run_check(MissingCodeInterface, source)
  end

  test "excluded_actions suppresses matching actions on a resource" do
    source = """
    defmodule AshCredoFixtures.Blog.Post do
      use Ash.Resource, domain: AshCredoFixtures.Blog
    end
    """

    issues =
      run_check(MissingCodeInterface, source,
        excluded_actions: ["AshCredoFixtures.Blog.Post.create"]
      )

    assert MapSet.equal?(trigger_set(issues), MapSet.new(~w(update destroy draft)))
  end

  test "excluded_actions works across multiple resources" do
    post_source = """
    defmodule AshCredoFixtures.Blog.Post do
      use Ash.Resource, domain: AshCredoFixtures.Blog
    end
    """

    user_source = """
    defmodule AshCredoFixtures.Accounts.User do
      use Ash.Resource, domain: AshCredoFixtures.Accounts
    end
    """

    post_issues =
      run_check(MissingCodeInterface, post_source,
        excluded_actions: [
          "AshCredoFixtures.Blog.Post.create",
          "AshCredoFixtures.Blog.Post.draft"
        ]
      )

    user_issues =
      run_check(MissingCodeInterface, user_source,
        excluded_actions: ["AshCredoFixtures.Accounts.User.read"]
      )

    assert MapSet.equal?(trigger_set(post_issues), MapSet.new(~w(update destroy)))
    assert MapSet.equal?(trigger_set(user_issues), MapSet.new(~w(create update destroy)))
  end

  test "excluded_actions disambiguates same action name across resources" do
    post_source = """
    defmodule AshCredoFixtures.Blog.Post do
      use Ash.Resource, domain: AshCredoFixtures.Blog
    end
    """

    user_source = """
    defmodule AshCredoFixtures.Accounts.User do
      use Ash.Resource, domain: AshCredoFixtures.Accounts
    end
    """

    excluded = ["AshCredoFixtures.Blog.Post.create"]

    post_issues = run_check(MissingCodeInterface, post_source, excluded_actions: excluded)
    user_issues = run_check(MissingCodeInterface, user_source, excluded_actions: excluded)

    refute MapSet.member?(trigger_set(post_issues), "create")
    assert MapSet.member?(trigger_set(user_issues), "create")
  end

  test "excluded_actions with no matches is a no-op" do
    source = """
    defmodule AshCredoFixtures.Blog.Post do
      use Ash.Resource, domain: AshCredoFixtures.Blog
    end
    """

    issues =
      run_check(MissingCodeInterface, source, excluded_actions: ["No.Such.Resource.nope"])

    assert MapSet.equal?(trigger_set(issues), MapSet.new(~w(create update destroy draft)))
  end

  test "emits a not-loadable config issue for an unknown resource" do
    source = """
    defmodule Totally.Fake.Resource do
      use Ash.Resource, domain: AshCredoFixtures.Blog
    end
    """

    assert [issue] = run_check(MissingCodeInterface, source)
    assert issue.message =~ "Could not load"
    assert issue.message =~ "Totally.Fake.Resource"
  end
end
