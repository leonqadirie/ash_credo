defmodule AshCredo.Check.Refactor.RaisingCallTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Refactor.RaisingCall
  alias AshCredo.Introspection.Compiled, as: CompiledIntrospection

  test "reports issue for Ash.read!" do
    source = """
    defmodule MyApp.Accounts do
      def list_users do
        Ash.read!(MyApp.User)
      end
    end
    """

    assert [issue] = run_check(RaisingCall, source)
    assert issue.trigger == "Ash.read!"
    assert issue.message =~ "Ash.read"
    assert issue.message =~ "raises on errors"
  end

  test "reports issue for Ash.create!" do
    source = """
    defmodule MyApp.Accounts do
      def register(attrs) do
        Ash.create!(MyApp.User, attrs)
      end
    end
    """

    assert [issue] = run_check(RaisingCall, source)
    assert issue.trigger == "Ash.create!"
  end

  test "reports issue for multi-arg bang call and suggests the non-bang variant in the message" do
    source = """
    defmodule MyApp.Accounts do
      def cleanup(query) do
        Ash.bulk_destroy!(query, :archive, %{})
      end
    end
    """

    assert [issue] = run_check(RaisingCall, source)
    assert issue.trigger == "Ash.bulk_destroy!"
    assert issue.message =~ "Prefer `Ash.bulk_destroy`"
  end

  test "reports issue for nested-module bang call (Ash.*.*!)" do
    source = """
    defmodule MyApp.Accounts do
      def parse_filter do
        Ash.Filter.parse!(MyApp.Post, [])
      end
    end
    """

    assert [issue] = run_check(RaisingCall, source)
    assert issue.trigger == "Ash.Filter.parse!"
    assert issue.message =~ "`Ash.Filter.parse`"
  end

  test "no issue for non-bang Ash.read" do
    source = """
    defmodule MyApp.Accounts do
      def list_users do
        Ash.read(MyApp.User)
      end
    end
    """

    assert [] = run_check(RaisingCall, source)
  end

  test "no issue for non-Ash bang call" do
    source = """
    defmodule MyApp.Accounts do
      def fetch! do
        SomeOtherLib.fetch!(MyApp.User)
      end
    end
    """

    assert [] = run_check(RaisingCall, source)
  end

  test "Ash.stream! is unflagged - no Ash.stream counterpart exists" do
    source = """
    defmodule MyApp.Accounts do
      def stream_users, do: Ash.stream!(MyApp.User)
    end
    """

    assert [] = run_check(RaisingCall, source)
  end

  test "Ash.Seed.seed! is unflagged - no Ash.Seed.seed counterpart exists" do
    source = """
    defmodule MyApp.Seeds do
      def seed_users do
        Ash.Seed.seed!(MyApp.User, %{name: "alice"})
      end
    end
    """

    assert [] = run_check(RaisingCall, source)
  end

  test "excluded_functions silences a bang that would otherwise be flagged" do
    source = """
    defmodule MyApp.Accounts do
      def list_users, do: Ash.read!(MyApp.User)
    end
    """

    assert [issue] = run_check(RaisingCall, source)
    assert issue.trigger == "Ash.read!"
    assert issue.line_no == 2
    assert [] = run_check(RaisingCall, source, excluded_functions: [{Ash, :read!}])
  end

  describe "message shape varies with the counterpart's return type" do
    test "tuple-returning APIs (Ash.read!) get the tuple-matching message" do
      source = """
      defmodule MyApp.Accounts do
        def list_users, do: Ash.read!(MyApp.User)
      end
      """

      assert [issue] = run_check(RaisingCall, source)
      assert issue.message =~ "Prefer `Ash.read`"
      assert issue.message =~ "`{:ok, _} | {:error, _}` tuple"
      assert issue.message =~ "callers expecting tuple results"
    end

    test "non-tuple helpers (Ash.Resource.Info.primary_action!) get a generic message" do
      # The non-bang `Ash.Resource.Info.primary_action/2` returns
      # `action | nil`, not `{:ok, _} | {:error, _}`. Telling users to
      # "match on the tuple" would be wrong advice. The check inspects the
      # non-bang counterpart's typespec via `Code.Typespec.fetch_specs/1`
      # and switches to a conservative "handle the returned value
      # explicitly" wording when the spec doesn't prove tuple semantics.
      source = """
      defmodule MyApp.Worker do
        def primary(resource), do: Ash.Resource.Info.primary_action!(resource, :read)
      end
      """

      assert [issue] = run_check(RaisingCall, source)
      assert issue.trigger == "Ash.Resource.Info.primary_action!"
      assert issue.message =~ "Prefer `Ash.Resource.Info.primary_action`"
      assert issue.message =~ "handle the returned value explicitly"
      refute issue.message =~ "tuple"
      refute issue.message =~ "{:ok, _}"
    end

    test "non-tuple helper still flagged - the check detects the raise, not the shape" do
      # Even with the generic wording, the diagnostic should fire: the
      # whole point is to call out that the bang raises on the "no result"
      # path, regardless of whether the success path returns a tuple.
      source = """
      defmodule MyApp.Worker do
        def attr(resource), do: Ash.Resource.Info.attribute!(resource, :id)
      end
      """

      assert [issue] = run_check(RaisingCall, source)
      assert issue.trigger == "Ash.Resource.Info.attribute!"
      assert issue.message =~ "handle the returned value explicitly"
    end
  end

  describe "flag_bang_only_apis: true" do
    test "flags Ash.stream! with the bang-only-API message" do
      source = """
      defmodule MyApp.Accounts do
        def stream_users, do: Ash.stream!(MyApp.User)
      end
      """

      assert [issue] = run_check(RaisingCall, source, flag_bang_only_apis: true)
      assert issue.trigger == "Ash.stream!"
      assert issue.message =~ "no non-bang counterpart"
      assert issue.message =~ "Ensure failures are properly handled"
      refute issue.message =~ "Prefer `Ash.stream`"
    end

    test "flags Ash.Seed.seed! with the bang-only-API message" do
      source = """
      defmodule MyApp.Seeds do
        def seed_users, do: Ash.Seed.seed!(MyApp.User, %{name: "alice"})
      end
      """

      assert [issue] = run_check(RaisingCall, source, flag_bang_only_apis: true)
      assert issue.trigger == "Ash.Seed.seed!"
      assert issue.message =~ "no non-bang counterpart"
    end

    test "still uses the 'Prefer non-bang' message for bangs that have a counterpart" do
      source = """
      defmodule MyApp.Accounts do
        def list_users, do: Ash.read!(MyApp.User)
      end
      """

      assert [issue] = run_check(RaisingCall, source, flag_bang_only_apis: true)
      assert issue.message =~ "Prefer `Ash.read`"
      refute issue.message =~ "no non-bang counterpart"
    end

    test "excluded_functions still wins over flag_bang_only_apis" do
      source = """
      defmodule MyApp.Accounts do
        def stream_users, do: Ash.stream!(MyApp.User)
      end
      """

      assert [] =
               run_check(RaisingCall, source,
                 flag_bang_only_apis: true,
                 excluded_functions: [{Ash, :stream!}]
               )
    end
  end

  test "trigger reflects the source spelling (aliased Ash); message stays canonical" do
    source = """
    defmodule MyApp.Accounts do
      alias Ash, as: A

      def list_users do
        A.read!(MyApp.User)
      end
    end
    """

    assert [issue] = run_check(RaisingCall, source)
    assert issue.trigger == "A.read!"
    assert issue.message =~ "Prefer `Ash.read`"
  end

  test "reports issue for bang call in a pipeline" do
    source = """
    defmodule MyApp.Accounts do
      def list_users do
        MyApp.User
        |> Ash.Query.for_read(:list)
        |> Ash.read!()
      end
    end
    """

    assert [issue] = run_check(RaisingCall, source)
    assert issue.trigger == "Ash.read!"
  end

  test "reports multiple bang calls separately" do
    source = """
    defmodule MyApp.Accounts do
      def churn(attrs, id) do
        user = Ash.create!(MyApp.User, attrs)
        Ash.destroy!(Ash.get!(MyApp.User, id))
        user
      end
    end
    """

    issues = run_check(RaisingCall, source)
    triggers = sorted_triggers(issues)
    assert triggers == ["Ash.create!", "Ash.destroy!", "Ash.get!"]
  end

  describe "excluded_paths" do
    test "skips files under test/ by default" do
      source = """
      defmodule MyApp.UserTest do
        def setup_user do
          Ash.create!(MyApp.User, %{})
        end
      end
      """

      assert [] = run_check(RaisingCall, source, __filename__: "test/my_app/user_test.exs")
    end

    test "skips nested directories under test/" do
      source = """
      Ash.create!(MyApp.User, %{})
      """

      assert [] = run_check(RaisingCall, source, __filename__: "test/support/factories.ex")
    end

    test "still flags lib/ files" do
      source = """
      defmodule MyApp.Accounts do
        def list_users, do: Ash.read!(MyApp.User)
      end
      """

      assert [issue] = run_check(RaisingCall, source, __filename__: "lib/my_app/accounts.ex")
      assert issue.trigger == "Ash.read!"
    end

    test "respects an empty excluded_paths override" do
      source = """
      Ash.read!(MyApp.User)
      """

      assert [issue] =
               run_check(RaisingCall, source,
                 __filename__: "test/my_app/user_test.exs",
                 excluded_paths: []
               )

      assert issue.trigger == "Ash.read!"
    end

    test "respects a custom excluded_paths list" do
      source = """
      Ash.read!(MyApp.User)
      """

      assert [] =
               run_check(RaisingCall, source,
                 __filename__: "priv/seeds.exs",
                 excluded_paths: ["priv"]
               )
    end

    test "skips absolute test paths even when the file sits directly under test/" do
      source = """
      Ash.create!(MyApp.User, %{})
      """

      assert [] =
               run_check(RaisingCall, source, __filename__: "/Users/dev/proj/test/foo_test.exs")
    end

    test "skips a single file when listed by full path" do
      source = """
      Ash.read!(MyApp.User)
      """

      assert [] =
               run_check(RaisingCall, source,
                 __filename__: "priv/seeds.exs",
                 excluded_paths: ["priv/seeds.exs"]
               )
    end
  end

  describe "excluded_functions" do
    test "default tuple silences only the configured {module, fun}" do
      source = """
      defmodule MyApp.Accounts do
        def stream_users, do: Ash.stream!(MyApp.User)
        def parse_filter, do: Ash.Filter.parse!(MyApp.Post, [])
      end
      """

      assert [issue] = run_check(RaisingCall, source)
      assert issue.trigger == "Ash.Filter.parse!"
    end

    test "module is required - bare-atom entries do not match" do
      source = """
      Ash.read!(MyApp.User)
      """

      assert [issue] = run_check(RaisingCall, source, excluded_functions: [:read!])
      assert issue.trigger == "Ash.read!"
    end

    test "silences specific nested-module bangs" do
      source = """
      Ash.Filter.parse!(MyApp.Post, [])
      """

      assert [] =
               run_check(RaisingCall, source,
                 excluded_functions: [{Ash, :stream!}, {Ash.Filter, :parse!}]
               )
    end
  end

  describe "code-interface bang detection (compiled pass)" do
    setup do
      CompiledIntrospection.clear_cache()
      :ok
    end

    test "flags resource-defined code-interface bang where name == action" do
      source = """
      defmodule MyApp.Worker do
        def archive_post(post) do
          AshCredoFixtures.Blog.Post.archive!(post)
        end
      end
      """

      assert [issue] = run_check(RaisingCall, source)
      assert issue.trigger == "AshCredoFixtures.Blog.Post.archive!"
      assert issue.message =~ "Prefer `AshCredoFixtures.Blog.Post.archive`"
      assert issue.message =~ "code-interface bang"
    end

    test "flags resource interface where the function name differs from action" do
      # define :published_posts, action: :published - generated function is
      # `published_posts!`, not `published!`. Matching by interface `:name`
      # (not `:action`) is the key correctness property of the lookup.
      source = """
      defmodule MyApp.Worker do
        def list, do: AshCredoFixtures.Blog.Post.published_posts!()
      end
      """

      assert [issue] = run_check(RaisingCall, source)
      assert issue.trigger == "AshCredoFixtures.Blog.Post.published_posts!"
      assert issue.message =~ "Prefer `AshCredoFixtures.Blog.Post.published_posts`"
    end

    test "flags domain-level code-interface bang from resource_references" do
      # AshCredoFixtures.Blog declares `define :publish_post, action: :publish`
      # inside its `resource AshCredoFixtures.Blog.Post do ... end` block.
      source = """
      defmodule MyApp.Worker do
        def publish(post), do: AshCredoFixtures.Blog.publish_post!(post)
      end
      """

      assert [issue] = run_check(RaisingCall, source)
      assert issue.trigger == "AshCredoFixtures.Blog.publish_post!"
      assert issue.message =~ "Prefer `AshCredoFixtures.Blog.publish_post`"
    end

    test "flags calculation-interface bang (define_calculation)" do
      source = """
      defmodule MyApp.Worker do
        def upcased, do: AshCredoFixtures.Blog.WithCalcInterface.upcased_title!()
      end
      """

      assert [issue] = run_check(RaisingCall, source)
      assert issue.trigger == "AshCredoFixtures.Blog.WithCalcInterface.upcased_title!"
      assert issue.message =~ "Prefer `AshCredoFixtures.Blog.WithCalcInterface.upcased_title`"
    end

    test "ignores non-Ash module bang calls" do
      source = """
      defmodule MyApp.Worker do
        def shout, do: AshCredoFixtures.Plain.hello!()
      end
      """

      assert [] = run_check(RaisingCall, source)
    end

    test "ignores bang calls to a real module that has no matching interface" do
      # AshCredoFixtures.Accounts.User has no `register` code interface.
      source = """
      defmodule MyApp.Worker do
        def register(attrs), do: AshCredoFixtures.Accounts.User.register!(attrs)
      end
      """

      assert [] = run_check(RaisingCall, source)
    end

    test "skips bang calls passing `stream?: true`" do
      # The non-bang variant of a read code interface rejects `stream?: true`,
      # so suggesting `Blog.list_posts(stream?: true)` would be wrong advice.
      source = """
      defmodule MyApp.Worker do
        def stream, do: AshCredoFixtures.Blog.list_posts!(stream?: true)
      end
      """

      assert [] = run_check(RaisingCall, source)
    end

    test "still flags the same interface without `stream?: true`" do
      source = """
      defmodule MyApp.Worker do
        def list, do: AshCredoFixtures.Blog.list_posts!()
      end
      """

      assert [issue] = run_check(RaisingCall, source)
      assert issue.trigger == "AshCredoFixtures.Blog.list_posts!"
    end

    test "still flags `stream?: true` on a non-read (update) interface" do
      # `publish_post` is `define :publish_post, action: :publish` where
      # `:publish` is an update action. `stream?: true` is meaningless on
      # an update and must not silence the diagnostic.
      source = """
      defmodule MyApp.Worker do
        def publish(post), do: AshCredoFixtures.Blog.publish_post!(post, stream?: true)
      end
      """

      assert [issue] = run_check(RaisingCall, source)
      assert issue.trigger == "AshCredoFixtures.Blog.publish_post!"
    end

    test "still flags `stream?: true` on a calculation interface" do
      # Calculation interfaces are not read actions; their non-bang twin
      # exists and `stream?: true` does not apply, so the call should flag.
      source = """
      defmodule MyApp.Worker do
        def upcased, do: AshCredoFixtures.Blog.WithCalcInterface.upcased_title!(stream?: true)
      end
      """

      assert [issue] = run_check(RaisingCall, source)
      assert issue.trigger == "AshCredoFixtures.Blog.WithCalcInterface.upcased_title!"
    end

    test "trigger reflects source spelling under an alias" do
      source = """
      defmodule MyApp.Worker do
        alias AshCredoFixtures.Blog, as: B

        def publish(post), do: B.publish_post!(post)
      end
      """

      assert [issue] = run_check(RaisingCall, source)
      assert issue.trigger == "B.publish_post!"
      assert issue.message =~ "Prefer `AshCredoFixtures.Blog.publish_post`"
    end

    test "excluded_functions silences code-interface bangs too" do
      source = """
      defmodule MyApp.Worker do
        def publish(post), do: AshCredoFixtures.Blog.publish_post!(post)
      end
      """

      assert [] =
               run_check(RaisingCall, source,
                 excluded_functions: [{Ash, :stream!}, {AshCredoFixtures.Blog, :publish_post!}]
               )
    end

    test "Ash.* syntactic pass still runs alongside the compiled pass" do
      source = """
      defmodule MyApp.Worker do
        def do_both do
          AshCredoFixtures.Blog.Post.archive!(:foo)
          Ash.read!(MyApp.User)
        end
      end
      """

      triggers = run_check(RaisingCall, source) |> sorted_triggers()
      assert triggers == ["Ash.read!", "AshCredoFixtures.Blog.Post.archive!"]
    end

    test "non-literal modules (apply, variable, __MODULE__) are skipped" do
      source = """
      defmodule MyApp.Worker do
        def via_apply(record), do: apply(AshCredoFixtures.Blog.Post, :archive!, [record])

        def via_var(mod, record), do: mod.archive!(record)
      end
      """

      assert [] = run_check(RaisingCall, source)
    end

    test "Ash.Domain.* nested bangs are still handled by the syntactic pass" do
      # Belt-and-braces: the compiled pass explicitly skips Ash.* so it never
      # double-counts these, but the syntactic pass must still flag them.
      source = """
      defmodule MyApp.Worker do
        def parse, do: Ash.Filter.parse!(MyApp.Post, [])
      end
      """

      assert [issue] = run_check(RaisingCall, source)
      assert issue.trigger == "Ash.Filter.parse!"
    end

    test "alias __MODULE__.Foo resolves to the enclosing module" do
      # `expand_alias` returns segments like `[{:__MODULE__, _, _}, :Post]`
      # for this pattern. The scanner substitutes `__MODULE__` with the
      # enclosing `defmodule`'s absolute segments so `Post.archive!()`
      # resolves to `AshCredoFixtures.Blog.Post.archive!` - same as the
      # fully-qualified spelling.
      source = """
      defmodule AshCredoFixtures.Blog do
        alias __MODULE__.Post

        def archive(post), do: Post.archive!(post)
      end
      """

      assert [issue] = run_check(RaisingCall, source)
      assert issue.trigger == "Post.archive!"
      assert issue.message =~ "Prefer `AshCredoFixtures.Blog.Post.archive`"
    end

    test "alias __MODULE__.Foo inside a non-Ash enclosing module does not crash" do
      # Regression for the original crash: before the scanner-level filter,
      # `[{:__MODULE__, _, _}, :Post]` segments reached `Module.concat/1`
      # and raised FunctionClauseError. With the resolution fix, the
      # segments resolve to `MyApp.Blog.Post`, which is not an Ash module,
      # so the call is silently skipped without crashing.
      source = """
      defmodule MyApp.Blog do
        alias __MODULE__.Post

        def archive(post), do: Post.archive!(post)
      end
      """

      assert [] = run_check(RaisingCall, source)
    end

    test "alias __MODULE__.Foo resolves through nested defmodules" do
      # `__MODULE__` inside the inner `defmodule Blog` body refers to
      # `AshCredoFixtures.Blog`, so `Post.archive!()` should resolve to
      # `AshCredoFixtures.Blog.Post.archive!` just like the flat case.
      source = """
      defmodule AshCredoFixtures do
        defmodule Blog do
          alias __MODULE__.Post

          def archive(post), do: Post.archive!(post)
        end
      end
      """

      assert [issue] = run_check(RaisingCall, source)
      assert issue.trigger == "Post.archive!"
      assert issue.message =~ "Prefer `AshCredoFixtures.Blog.Post.archive`"
    end
  end

  describe "bang-only APIs (no non-bang counterpart)" do
    setup do
      CompiledIntrospection.clear_cache()
      :ok
    end

    test "skips bangs whose module exports no non-bang twin" do
      source = """
      defmodule MyApp.Seeds do
        def upsert(attrs), do: Ash.Seed.upsert!(MyApp.User, attrs)
      end
      """

      assert [] = run_check(RaisingCall, source)
    end

    test "skips `Ash.*` bangs whose module isn't loadable" do
      # Typo'd or otherwise unresolvable `Ash.*` modules used to fall
      # through `compute_counterpart`'s `_ -> true` clause and emit a
      # "Prefer `Ash.NoSuchSubmod.fun`" suggestion - bad advice naming
      # a function we can't confirm exists. The tri-state counterpart
      # result now classifies these as `:not_loadable` and skips.
      source = """
      defmodule MyApp.Worker do
        def boom, do: Ash.NoSuchSubmod.fun!(:arg)
      end
      """

      assert [] = run_check(RaisingCall, source)
    end

    test "still skips `:not_loadable` even with `flag_bang_only_apis: true`" do
      # We don't promote `:not_loadable` to a bang-only diagnostic - the
      # whole point of the tri-state is to distinguish "definitely no
      # counterpart" from "couldn't tell". Only the former warrants the
      # generic "ensure failures are handled" message.
      source = """
      defmodule MyApp.Worker do
        def boom, do: Ash.NoSuchSubmod.fun!(:arg)
      end
      """

      assert [] = run_check(RaisingCall, source, flag_bang_only_apis: true)
    end
  end
end
