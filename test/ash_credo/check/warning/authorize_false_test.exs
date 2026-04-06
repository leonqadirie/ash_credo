defmodule AshCredo.Check.Warning.AuthorizeFalseTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Warning.AuthorizeFalse

  test "reports issue for authorize?: false as direct argument" do
    source = """
    defmodule MyApp.Accounts do
      def list_users do
        Ash.read!(MyApp.User, authorize?: false)
      end
    end
    """

    assert [issue] = run_check(AuthorizeFalse, source)
    assert issue.trigger == "authorize?: false"
  end

  test "reports issue for authorize?: false in a keyword list with other options" do
    source = """
    defmodule MyApp.Accounts do
      def list_users(actor) do
        Ash.read!(MyApp.User, actor: actor, authorize?: false)
      end
    end
    """

    assert [issue] = run_check(AuthorizeFalse, source)
    assert issue.trigger == "authorize?: false"
  end

  test "reports issue for authorize?: false in a pipeline" do
    source = """
    defmodule MyApp.Accounts do
      def list_users do
        MyApp.User
        |> Ash.Query.for_read(:list)
        |> Ash.read!(authorize?: false)
      end
    end
    """

    assert [issue] = run_check(AuthorizeFalse, source)
    assert issue.trigger == "authorize?: false"
  end

  test "no issue for authorize?: true" do
    source = """
    defmodule MyApp.Accounts do
      def list_users do
        Ash.read!(MyApp.User, authorize?: true)
      end
    end
    """

    assert [] = run_check(AuthorizeFalse, source)
  end

  test "no issue for calls without authorize? option" do
    source = """
    defmodule MyApp.Accounts do
      def list_users(actor) do
        Ash.read!(MyApp.User, actor: actor)
      end
    end
    """

    assert [] = run_check(AuthorizeFalse, source)
  end

  test "reports issue for authorize?: false in non-Ash calls by default" do
    source = """
    defmodule MyApp.Accounts do
      def do_thing do
        SomeOtherLib.run(query, authorize?: false)
      end
    end
    """

    assert [issue] = run_check(AuthorizeFalse, source)
    assert issue.trigger == "authorize?: false"
  end

  test "skips non-Ash calls when include_non_ash_calls is false" do
    source = """
    defmodule MyApp.Accounts do
      def do_thing do
        SomeOtherLib.run(query, authorize?: false)
      end
    end
    """

    assert [] = run_check(AuthorizeFalse, source, include_non_ash_calls: false)
  end

  test "still detects Ash calls when include_non_ash_calls is false" do
    source = """
    defmodule MyApp.Accounts do
      def list_users do
        Ash.read!(MyApp.User, authorize?: false)
      end
    end
    """

    assert [issue] = run_check(AuthorizeFalse, source, include_non_ash_calls: false)
    assert issue.trigger == "authorize?: false"
  end

  test "still detects action DSL when include_non_ash_calls is false" do
    source = """
    defmodule MyApp.User do
      use Ash.Resource

      actions do
        read :list, authorize?: false
      end
    end
    """

    assert [issue] = run_check(AuthorizeFalse, source, include_non_ash_calls: false)
    assert issue.trigger == "authorize?: false"
  end

  test "reports issue for authorize?: false with aliased Ash module" do
    source = """
    defmodule MyApp.Accounts do
      alias Ash, as: A

      def list_users do
        A.read!(MyApp.User, authorize?: false)
      end
    end
    """

    assert [issue] = run_check(AuthorizeFalse, source)
    assert issue.trigger == "authorize?: false"
  end

  test "reports issue for authorize?: false with aliased Ash submodule" do
    source = """
    defmodule MyApp.Accounts do
      alias Ash.Query

      def list_users do
        query = Query.for_read(MyApp.User, :list)
        Ash.read!(query, authorize?: false)
      end
    end
    """

    assert [issue] = run_check(AuthorizeFalse, source)
    assert issue.trigger == "authorize?: false"
  end

  test "reports issue for inline authorize?: false on an action" do
    source = """
    defmodule MyApp.User do
      use Ash.Resource

      actions do
        read :list, authorize?: false
      end
    end
    """

    assert [issue] = run_check(AuthorizeFalse, source)
    assert issue.trigger == "authorize?: false"
  end

  test "reports issue for authorize?: false in action do block" do
    source = """
    defmodule MyApp.User do
      use Ash.Resource

      actions do
        create :create do
          authorize? false
        end
      end
    end
    """

    assert [issue] = run_check(AuthorizeFalse, source)
    assert issue.trigger == "authorize?: false"
  end

  test "reports issues for multiple actions with authorize?: false" do
    source = """
    defmodule MyApp.User do
      use Ash.Resource

      actions do
        read :list, authorize?: false
        create :create, authorize?: false
      end
    end
    """

    assert [_, _] = run_check(AuthorizeFalse, source)
  end

  test "no issue for action with authorize?: true" do
    source = """
    defmodule MyApp.User do
      use Ash.Resource

      actions do
        read :list, authorize?: true
      end
    end
    """

    assert [] = run_check(AuthorizeFalse, source)
  end

  test "no issue for action without authorize? option" do
    source = """
    defmodule MyApp.User do
      use Ash.Resource

      actions do
        read :list
      end
    end
    """

    assert [] = run_check(AuthorizeFalse, source)
  end

  test "reports issue for authorize?: false in a variable assignment" do
    source = """
    defmodule MyApp.Accounts do
      def list_users do
        opts = [authorize?: false]
        Ash.read!(MyApp.User, opts)
      end
    end
    """

    assert [issue] = run_check(AuthorizeFalse, source)
    assert issue.trigger == "authorize?: false"
  end
end
