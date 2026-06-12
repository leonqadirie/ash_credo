defmodule AshCredo.Check.Warning.MissingPrepareWrapperTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Warning.MissingPrepareWrapper

  test "reports issue for naked build in read action" do
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

    assert [issue] = run_check(MissingPrepareWrapper, source)
    assert issue.trigger == "build"
    assert issue.line_no == 6
    assert issue.message =~ "prepare"
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

    assert [] = run_check(MissingPrepareWrapper, source)
  end

  test "reports issue for naked set_context in read action" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        read :search do
          set_context(%{tracing: true})
        end
      end
    end
    """

    assert [issue] = run_check(MissingPrepareWrapper, source)
    assert issue.trigger == "set_context"
  end

  test "reports issue for naked preparation builtins in generic action" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        action :compute, :integer do
          set_context(%{tracing: true})
          run fn _input, _context -> {:ok, 1} end
        end
      end
    end
    """

    assert [issue] = run_check(MissingPrepareWrapper, source)
    assert issue.trigger == "set_context"
  end

  test "does not scan create/update/destroy actions (preparation builtins do not compile there)" do
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

        destroy :archive do
          set_context(%{a: 1})
        end
      end
    end
    """

    assert [] = run_check(MissingPrepareWrapper, source)
  end

  test "reports issue for naked build in pipeline body" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      pipelines do
        pipeline :sorted do
          build(sort: [inserted_at: :desc])
        end
      end
    end
    """

    assert [issue] = run_check(MissingPrepareWrapper, source)
    assert issue.trigger == "build"
    assert issue.line_no == 6
  end

  test "no issue when build is wrapped in prepare inside pipeline body" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      pipelines do
        pipeline :sorted do
          prepare build(sort: [inserted_at: :desc])
        end
      end
    end
    """

    assert [] = run_check(MissingPrepareWrapper, source)
  end

  test "does not flag naked set_context in pipeline body (MissingChangeWrapper's job)" do
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

    assert [] = run_check(MissingPrepareWrapper, source)
  end

  test "no issue for non-preparation calls in read action body" do
    source = """
    defmodule MyApp.Post do
      use Ash.Resource, domain: MyApp.Blog

      actions do
        read :search do
          argument :query, :string
          prepare build(sort: [:id])
        end
      end
    end
    """

    assert [] = run_check(MissingPrepareWrapper, source)
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

    assert [] = run_check(MissingPrepareWrapper, source)
  end

  test "ignores non-Ash modules" do
    source = """
    defmodule MyApp.Utils do
      def query, do: build(sort: [:id])
    end
    """

    assert [] = run_check(MissingPrepareWrapper, source)
  end
end
