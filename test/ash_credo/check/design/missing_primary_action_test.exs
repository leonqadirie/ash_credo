defmodule AshCredo.Check.Design.MissingPrimaryActionTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Design.MissingPrimaryAction
  alias AshCredo.Introspection.Compiled, as: CompiledIntrospection

  # Tests reference real fixture modules from `test/support/fixtures/ash_fixtures.ex`
  # so that compiled-introspection (`Ash.Resource.Info.actions/1`) returns the
  # fully-resolved action list:
  #
  #   * `AshCredoFixtures.Blog.Post` - has `read :read, primary?: true` plus
  #     multiple non-primary reads and multiple non-primary updates, and a
  #     primary `:create` via `defaults [:create, :update, :destroy]`.
  #   * `AshCredoFixtures.Blog.Tag` - has `create :create_basic` and
  #     `create :create_with_slug`, neither primary. Failure-path fixture.
  #   * `AshCredoFixtures.Accounts.User` - `defaults [:create, :read, :update, :destroy]`,
  #     single action of each type. Happy-path fixture.

  setup do
    CompiledIntrospection.clear_cache()
    :ok
  end

  test "no issue for a resource with a single primary action per type" do
    source = """
    defmodule AshCredoFixtures.Accounts.User do
      use Ash.Resource, domain: AshCredoFixtures.Accounts
    end
    """

    assert [] = run_check(MissingPrimaryAction, source)
  end

  test "no issue when multiple reads exist but one is marked primary" do
    # Blog.Post has :read (primary), :published, :draft - three reads total
    # but :read is primary so no issue should fire for the read type.
    source = """
    defmodule AshCredoFixtures.Blog.Post do
      use Ash.Resource, domain: AshCredoFixtures.Blog
    end
    """

    assert [] = run_check(MissingPrimaryAction, source)
  end

  test "reports an issue when multiple creates exist without primary" do
    # Blog.Tag has :create_basic and :create_with_slug, neither primary.
    source = """
    defmodule AshCredoFixtures.Blog.Tag do
      use Ash.Resource, domain: AshCredoFixtures.Blog
    end
    """

    assert [issue] = run_check(MissingPrimaryAction, source)
    assert issue.trigger == "create"
    assert issue.message =~ "Multiple `create` actions"
    assert issue.message =~ "primary?"
  end

  test "ignores modules that are not Ash resources" do
    source = """
    defmodule MyApp.Utils do
      def hello, do: :world
    end
    """

    assert [] = run_check(MissingPrimaryAction, source)
  end

  test "emits a not-loadable config issue for an unknown resource" do
    source = """
    defmodule Totally.Fake.Resource do
      use Ash.Resource, domain: AshCredoFixtures.Blog
    end
    """

    assert [issue] = run_check(MissingPrimaryAction, source)
    assert issue.message =~ "Could not load"
    assert issue.message =~ "Totally.Fake.Resource"
  end

  test "deduplicates :not_loadable diagnostics across multiple references to the same module" do
    # Two source files (or two run_check invocations) referencing the same
    # unloadable module should produce only ONE diagnostic. Verifies the
    # `Compiled.with_unique_not_loadable/2` dedup wired through
    # `:not_loadable` branches in every compile-dependent check.
    first_source = """
    defmodule Totally.Fake.Dedup do
      use Ash.Resource, domain: AshCredoFixtures.Blog
    end
    """

    second_source = """
    defmodule Totally.Fake.Dedup do
      use Ash.Resource, domain: AshCredoFixtures.Blog
    end
    """

    assert [issue] = run_check(MissingPrimaryAction, first_source)
    assert issue.message =~ "Could not load"
    assert issue.message =~ "Totally.Fake.Dedup"

    # Second invocation against the same broken module — already warned, so
    # the dedup helper returns [] without re-emitting.
    assert [] = run_check(MissingPrimaryAction, second_source)
  end
end
