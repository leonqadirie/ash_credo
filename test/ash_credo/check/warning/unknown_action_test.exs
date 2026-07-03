defmodule AshCredo.Check.Warning.UnknownActionTest do
  use AshCredo.CheckCase, clear_cache: true

  alias AshCredo.Check.Warning.UnknownAction

  # Tests reference the real fixture `AshCredoFixtures.Blog.Post`, which has
  # actions `:read` (primary), `:published`, `:draft`, `:publish`, `:archive`,
  # `:create`, `:update`, `:destroy`. The check resolves the resource via
  # `Compiled.inspect_module/1` and then asks `Compiled.action/2` whether
  # the literal action exists.

  describe "unknown action detection" do
    test "emits an issue with a jaro-distance suggestion for a near-miss typo" do
      source = """
      defmodule AshCredoFixtures.Blog do
        def list do
          Ash.read!(AshCredoFixtures.Blog.Post, action: :publishd)
        end
      end
      """

      assert [issue] = run_check(UnknownAction, source)
      assert issue.message =~ "Unknown action"
      assert issue.message =~ ":publishd"
      assert issue.message =~ "Did you mean"
      assert issue.message =~ ":published"
      assert issue.trigger == "Ash.read!"
    end

    test "omits the hint when no close match exists" do
      source = """
      defmodule AshCredoFixtures.Blog do
        def list do
          Ash.read!(AshCredoFixtures.Blog.Post, action: :xyzzyqqq)
        end
      end
      """

      assert [issue] = run_check(UnknownAction, source)
      assert issue.message =~ "Unknown action"
      assert issue.message =~ ":xyzzyqqq"
      refute issue.message =~ "Did you mean"
    end

    test "does not emit when the action exists on the resource" do
      source = """
      defmodule AshCredoFixtures.Blog do
        def list do
          Ash.read!(AshCredoFixtures.Blog.Post, action: :published)
        end
      end
      """

      assert [] = run_check(UnknownAction, source)
    end

    test "fires for an Ash.Query.for_read builder (pattern D)" do
      source = """
      defmodule AshCredoFixtures.Blog do
        def query do
          Ash.Query.for_read(AshCredoFixtures.Blog.Post, :nope)
        end
      end
      """

      assert [issue] = run_check(UnknownAction, source)
      assert issue.message =~ "Unknown action"
      assert issue.message =~ ":nope"
      assert issue.trigger == "Ash.Query.for_read"
    end

    test "fires for a builder aliased via require ... as:" do
      # `require Ash.Query, as: Query` sets up the alias like
      # `alias Ash.Query, as: Query`, so the call must resolve the same way.
      source = """
      defmodule AshCredoFixtures.Blog do
        require Ash.Query, as: Query

        def query do
          Query.for_read(AshCredoFixtures.Blog.Post, :nope)
        end
      end
      """

      assert [issue] = run_check(UnknownAction, source)
      assert issue.message =~ "Unknown action"
      assert issue.message =~ ":nope"
      assert issue.trigger == "Ash.Query.for_read"
    end

    test "fires for an Ash.Changeset.for_create builder (pattern D)" do
      source = """
      defmodule AshCredoFixtures.Blog do
        def build do
          Ash.Changeset.for_create(AshCredoFixtures.Blog.Post, :nope)
        end
      end
      """

      assert [issue] = run_check(UnknownAction, source)
      assert issue.message =~ "Unknown action"
      assert issue.message =~ ":nope"
      assert issue.trigger == "Ash.Changeset.for_create"
    end

    test "is silent for a resource-first builder naming a real action" do
      source = """
      defmodule AshCredoFixtures.Blog do
        def build do
          Ash.Changeset.for_create(AshCredoFixtures.Blog.Post, :create)
        end
      end
      """

      assert [] = run_check(UnknownAction, source)
    end

    test "is silent for plain Elixir modules and non-Ash calls" do
      source = """
      defmodule MyApp.Utils do
        def hello, do: :world
      end
      """

      assert [] = run_check(UnknownAction, source)
    end

    test "is silent for unloadable resources (owned by UseCodeInterface)" do
      # Unloadable resources are reported by `Refactor.UseCodeInterface`'s
      # `:not_loadable` branch (gated on `enforce_code_interface_outside_domain`).
      # Emitting a second diagnostic from `UnknownAction` would just double the
      # noise, so this check skips them silently.
      source = """
      defmodule AshCredoFixtures.Blog do
        def list do
          Ash.read!(Totally.Fake.Resource, action: :publishd)
        end
      end
      """

      assert [] = run_check(UnknownAction, source)
    end
  end
end
