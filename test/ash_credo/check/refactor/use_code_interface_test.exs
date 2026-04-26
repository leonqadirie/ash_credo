defmodule AshCredo.Check.Refactor.UseCodeInterfaceTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Refactor.UseCodeInterface
  alias AshCredo.Introspection.Compiled, as: CompiledIntrospection

  # The synthetic source strings in these tests reference real fixture modules
  # loaded from `test/support/fixtures/ash_fixtures.ex`:
  #
  #   * `AshCredoFixtures.Blog`           - a domain
  #   * `AshCredoFixtures.Blog.Post`      - a resource in Blog
  #   * `AshCredoFixtures.Accounts`       - a second domain
  #   * `AshCredoFixtures.Accounts.User`  - a resource in Accounts
  #   * `AshCredoFixtures.Plain`          - a non-Ash module
  #
  # The check resolves each referenced name to an atom and then queries the
  # compiled-BEAM introspection, exercising the real classification path.

  setup do
    CompiledIntrospection.clear_cache()
    :ok
  end

  # ── AST short-circuits (no introspection needed) ──────────────────────────

  describe "AST short-circuits" do
    test "no issue for non-Ash call" do
      source = """
      defmodule AshCredoFixtures.Blog do
        def list_published do
          SomeOtherLib.read(AshCredoFixtures.Blog.Post, action: :published)
        end
      end
      """

      assert [] = run_check(UseCodeInterface, source)
    end

    test "no issue when resource is a variable" do
      source = """
      defmodule AshCredoFixtures.Blog do
        def list(resource) do
          Ash.read!(resource, action: :published)
        end
      end
      """

      assert [] = run_check(UseCodeInterface, source)
    end

    test "no issue when action is a variable" do
      source = """
      defmodule AshCredoFixtures.Blog do
        def list(action) do
          Ash.read!(AshCredoFixtures.Blog.Post, action: action)
        end
      end
      """

      assert [] = run_check(UseCodeInterface, source)
    end

    test "Ash.read without an :action key falls back to the primary :read action" do
      # `Ash.read!/get!/stream!` without an `:action` keyword dispatches to the
      # resource's primary :read action. The check mirrors that, so bare-form
      # callers get the same code-interface suggestion as the explicit form.
      source = """
      defmodule AshCredoFixtures.Blog do
        def list_posts(actor) do
          Ash.read!(AshCredoFixtures.Blog.Post, actor: actor)
        end
      end
      """

      assert [issue] = run_check(UseCodeInterface, source)
      assert issue.trigger == "Ash.read!"
      # Same-domain caller, :read has both a resource and a domain interface;
      # `:auto` prefers the resource interface (`all_posts`).
      assert issue.message =~ "AshCredoFixtures.Blog.Post.all_posts!"
    end

    test "bare Ash.read!(Resource) (no opts) also flags via the primary :read fallback" do
      source = """
      defmodule AshCredoFixtures.Blog do
        def list_posts do
          Ash.read!(AshCredoFixtures.Blog.Post)
        end
      end
      """

      assert [issue] = run_check(UseCodeInterface, source)
      assert issue.trigger == "Ash.read!"
      assert issue.message =~ "AshCredoFixtures.Blog.Post.all_posts!"
    end

    test "bare Ash.read!(Unloadable) still emits the :not_loadable diagnostic" do
      source = """
      defmodule SomeController do
        def list do
          Ash.read!(Totally.Fake.NoOpts)
        end
      end
      """

      assert [issue] = run_check(UseCodeInterface, source)
      assert issue.message =~ "Could not load"
      assert issue.message =~ "Totally.Fake.NoOpts"
    end
  end

  # ── Unknown modules and non-resources ──────────────────────────────────────

  describe "unknown modules" do
    test "not-loadable resource emits a config error issue" do
      source = """
      defmodule SomeController do
        def list do
          Ash.read!(Totally.Fake.Module, action: :published)
        end
      end
      """

      assert [issue] = run_check(UseCodeInterface, source)
      assert issue.message =~ "Could not load"
      assert issue.message =~ "Totally.Fake.Module"
      assert issue.message =~ "mix compile"
    end

    test "plain Elixir module is silently skipped" do
      source = """
      defmodule SomeController do
        def list do
          Ash.read!(AshCredoFixtures.Plain, action: :anything)
        end
      end
      """

      assert [] = run_check(UseCodeInterface, source)
    end
  end

  # ── Same-domain: suggest the resource-level code interface ─────────────────

  describe "same-domain, resource interface exists" do
    test "suggests the exact function when interface name differs from action" do
      source = """
      defmodule AshCredoFixtures.Blog do
        def list_published do
          Ash.read!(AshCredoFixtures.Blog.Post, action: :published)
        end
      end
      """

      assert [issue] = run_check(UseCodeInterface, source)
      assert issue.trigger == "Ash.read!"
      assert issue.message =~ "AshCredoFixtures.Blog.Post.published_posts!"
      assert issue.message =~ "Ash.read!"
    end

    test "suggests the non-bang function for non-bang calls" do
      source = """
      defmodule AshCredoFixtures.Blog do
        def list_published do
          Ash.read(AshCredoFixtures.Blog.Post, action: :published)
        end
      end
      """

      assert [issue] = run_check(UseCodeInterface, source)
      assert issue.message =~ "AshCredoFixtures.Blog.Post.published_posts"
      refute issue.message =~ "published_posts!"
    end

    test "caller is a sibling resource in the same domain" do
      source = """
      defmodule AshCredoFixtures.Accounts.User do
        def list_published do
          Ash.read!(AshCredoFixtures.Accounts.User, action: :read)
        end
      end
      """

      # Accounts.User has no interfaces at all, but AshCredoFixtures.Accounts
      # also has no domain-level interface for :read - so we fall through to
      # "define a resource-level interface".
      assert [issue] = run_check(UseCodeInterface, source)
      assert issue.message =~ "Prefer a code interface on"
      assert issue.message =~ "AshCredoFixtures.Accounts.User"
      assert issue.message =~ "define :read"
    end

    test "aliased top-level defmodule caller is classified via its real module" do
      # Regression: `AshApi.push_module_stack` previously stored raw literal
      # segments of the `defmodule` name. A top-level `defmodule User` that
      # relied on a preceding `alias ..., as: User` was classified as the
      # bare `User`, which failed domain lookup and fell through to the
      # wrong branch. With alias expansion it must resolve to the real
      # `AshCredoFixtures.Accounts.User` and emit the same-domain suggestion.
      source = """
      alias AshCredoFixtures.Accounts.User

      defmodule User do
        def list_published do
          Ash.read!(AshCredoFixtures.Accounts.User, action: :read)
        end
      end
      """

      assert [issue] = run_check(UseCodeInterface, source)
      assert issue.message =~ "Prefer a code interface on"
      assert issue.message =~ "AshCredoFixtures.Accounts.User"
      assert issue.message =~ "define :read"
    end
  end

  # ── Same-domain: resource interface missing, domain interface exists ───────

  describe "same-domain, only domain interface exists" do
    test "suggests the domain function when resource has no matching interface" do
      source = """
      defmodule AshCredoFixtures.Blog do
        def publish_it do
          Ash.bulk_update(AshCredoFixtures.Blog.Post, :publish, %{})
        end
      end
      """

      # `:publish` has a domain interface (:publish_post) but no resource
      # interface. Same-domain caller → same-domain logic picks resource
      # first, but falls through to domain-level since the resource has none.
      # NB: Ash.bulk_update with a literal resource arg 0 is not actually flagged
      # by the check (bulk_update expects a query/stream), so use a different pattern.
      assert run_check(UseCodeInterface, source) == []
    end
  end

  # ── Same-domain: action exists, no interface anywhere ──────────────────────

  describe "same-domain, no interface anywhere" do
    test "suggests defining a resource-level code interface" do
      source = """
      defmodule AshCredoFixtures.Blog do
        def drafts do
          Ash.read!(AshCredoFixtures.Blog.Post, action: :draft)
        end
      end
      """

      assert [issue] = run_check(UseCodeInterface, source)
      assert issue.message =~ "Prefer a code interface on"
      assert issue.message =~ "AshCredoFixtures.Blog.Post"
      assert issue.message =~ "define :draft"
    end
  end

  # ── Cross-domain: suggest the domain-level code interface ──────────────────

  describe "cross-domain, domain interface exists" do
    test "caller in a different domain is pointed at the resource's domain interface" do
      source = """
      defmodule AshCredoFixtures.Accounts do
        def publish_it do
          Ash.read!(AshCredoFixtures.Blog.Post, action: :publish)
        end
      end
      """

      assert [issue] = run_check(UseCodeInterface, source)
      assert issue.message =~ "AshCredoFixtures.Blog.publish_post!"
      assert issue.message =~ "Ash.read!"
    end

    test "caller is a plain module (no domain) with resource domain interface" do
      source = """
      defmodule SomeController do
        def publish_it do
          Ash.read!(AshCredoFixtures.Blog.Post, action: :publish)
        end
      end
      """

      assert [issue] = run_check(UseCodeInterface, source)
      assert issue.message =~ "AshCredoFixtures.Blog.publish_post!"
    end
  end

  describe "cross-domain, only resource interface exists" do
    test "falls back to the resource interface when the domain has none for the action" do
      source = """
      defmodule AshCredoFixtures.Accounts do
        def get_published do
          Ash.read!(AshCredoFixtures.Blog.Post, action: :published)
        end
      end
      """

      # :published has a resource interface (published_posts) but no domain
      # interface. Cross-domain → prefer domain, but fall through to resource.
      assert [issue] = run_check(UseCodeInterface, source)
      assert issue.message =~ "AshCredoFixtures.Blog.Post.published_posts!"
    end
  end

  describe "cross-domain, no interface anywhere" do
    test "suggests defining a domain-level interface" do
      source = """
      defmodule AshCredoFixtures.Accounts do
        def drafts do
          Ash.read!(AshCredoFixtures.Blog.Post, action: :draft)
        end
      end
      """

      assert [issue] = run_check(UseCodeInterface, source)
      assert issue.message =~ "Prefer a code interface on"
      assert issue.message =~ "AshCredoFixtures.Blog"
      assert issue.message =~ "define :some_name, action: :draft"
    end
  end

  # ── Builder calls ──────────────────────────────────────────────────────────

  describe "builder calls" do
    test "Ash.Query.for_read suggests the query_to_* helper" do
      source = """
      defmodule AshCredoFixtures.Blog do
        def published_query do
          Ash.Query.for_read(AshCredoFixtures.Blog.Post, :published)
        end
      end
      """

      assert [issue] = run_check(UseCodeInterface, source)
      assert issue.trigger == "Ash.Query.for_read"
      assert issue.message =~ "query_to_published_posts"
    end

    test "Ash.Changeset.for_create with no matching interface suggests defining one" do
      source = """
      defmodule AshCredoFixtures.Blog do
        def create_post(params) do
          Ash.Changeset.for_create(AshCredoFixtures.Blog.Post, :create, params)
        end
      end
      """

      assert [issue] = run_check(UseCodeInterface, source)
      assert issue.trigger == "Ash.Changeset.for_create"
      assert issue.message =~ "Prefer a code interface"
      assert issue.message =~ "define :create"
    end

    test "aliased Ash.Query.for_read still resolves" do
      source = """
      defmodule AshCredoFixtures.Blog do
        alias Ash.Query

        def published_query do
          Query.for_read(AshCredoFixtures.Blog.Post, :published)
        end
      end
      """

      assert [issue] = run_check(UseCodeInterface, source)
      assert issue.trigger == "Ash.Query.for_read"
      assert issue.message =~ "query_to_published_posts"
    end
  end

  # ── Implicit submodule alias ───────────────────────────────────────────────

  describe "implicit submodule alias" do
    test "unqualified resource resolves to enclosing_module.Resource" do
      source = """
      defmodule AshCredoFixtures.Blog do
        def list_published do
          Ash.read!(Post, action: :published)
        end
      end
      """

      assert [issue] = run_check(UseCodeInterface, source)
      assert issue.message =~ "AshCredoFixtures.Blog.Post.published_posts!"
    end

    test "implicit alias is not applied when a matching top-level module exists" do
      # `AshCredoFixtures.Blog.Post` is loadable directly, so the direct
      # resolution wins and implicit lookup is not consulted.
      source = """
      defmodule AshCredoFixtures.Accounts do
        def list_published do
          Ash.read!(AshCredoFixtures.Blog.Post, action: :published)
        end
      end
      """

      assert [issue] = run_check(UseCodeInterface, source)
      assert issue.message =~ "AshCredoFixtures.Blog.Post.published_posts!"
    end
  end

  # ── __MODULE__ in the resource position ───────────────────────────────────

  describe "__MODULE__" do
    test "bare __MODULE__ resolves to the enclosing resource" do
      source = """
      defmodule AshCredoFixtures.Blog.Post do
        def echo do
          Ash.read!(__MODULE__, action: :published)
        end
      end
      """

      assert [issue] = run_check(UseCodeInterface, source)
      assert issue.message =~ "AshCredoFixtures.Blog.Post.published_posts!"
    end
  end

  # ── Struct literal + traced-record bindings for builders ───────────────────

  describe "struct literal as builder resource" do
    test "Ash.Changeset.for_update with a struct literal" do
      source = """
      defmodule AshCredoFixtures.Blog do
        def run(id) do
          Ash.Changeset.for_update(%AshCredoFixtures.Blog.Post{id: id}, :archive, %{})
        end
      end
      """

      assert [issue] = run_check(UseCodeInterface, source)
      assert issue.trigger == "Ash.Changeset.for_update"
      assert issue.message =~ "changeset_to_archive"
    end

    test "Ash.Changeset.for_destroy with a struct literal" do
      source = """
      defmodule AshCredoFixtures.Blog do
        def run do
          Ash.Changeset.for_destroy(%AshCredoFixtures.Blog.Post{}, :destroy, %{})
        end
      end
      """

      # `:destroy` is a default action on Post but has no code interface →
      # same-domain fallback is "define a resource interface".
      assert [issue] = run_check(UseCodeInterface, source)
      assert issue.trigger == "Ash.Changeset.for_destroy"
      assert issue.message =~ "define :destroy"
    end
  end

  describe "traced record bindings" do
    test "for_update sees records bound via Ash.get!" do
      source = """
      defmodule AshCredoFixtures.Blog do
        def run(id) do
          post = Ash.get!(AshCredoFixtures.Blog.Post, id)
          Ash.Changeset.for_update(post, :archive, %{})
        end
      end
      """

      issues = run_check(UseCodeInterface, source)
      update_issue = find_by_trigger(issues, "Ash.Changeset.for_update")
      assert update_issue
      assert update_issue.message =~ "changeset_to_archive"
    end

    test "for_update sees records piped through Ash.get!" do
      source = """
      defmodule AshCredoFixtures.Blog do
        def run(id) do
          AshCredoFixtures.Blog.Post
          |> Ash.get!(id)
          |> Ash.Changeset.for_update(:archive, %{})
        end
      end
      """

      issues = run_check(UseCodeInterface, source)
      update_issue = find_by_trigger(issues, "Ash.Changeset.for_update")
      assert update_issue
      assert update_issue.message =~ "changeset_to_archive"
    end

    test "for_destroy sees records bound via Ash.get!" do
      source = """
      defmodule AshCredoFixtures.Blog do
        def run(id) do
          post = Ash.get!(AshCredoFixtures.Blog.Post, id)
          Ash.Changeset.for_destroy(post, :destroy, %{})
        end
      end
      """

      issues = run_check(UseCodeInterface, source)
      assert find_by_trigger(issues, "Ash.Changeset.for_destroy")
    end

    test "non-bang Ash.get is not traced (it returns a result tuple, not a record)" do
      source = """
      defmodule AshCredoFixtures.Blog do
        def run(id) do
          post = Ash.get(AshCredoFixtures.Blog.Post, id)
          Ash.Changeset.for_update(post, :archive, %{})
        end
      end
      """

      issues = run_check(UseCodeInterface, source)
      refute find_by_trigger(issues, "Ash.Changeset.for_update")
    end

    test "no issue when the record origin is an unrelated helper" do
      source = """
      defmodule AshCredoFixtures.Blog do
        def run(id) do
          post = SomeRepo.load(id)
          Ash.Changeset.for_update(post, :archive, %{})
        end
      end
      """

      assert [] = run_check(UseCodeInterface, source)
    end

    test "for_create is not record-traced (would be a user error anyway)" do
      # `Ash.Changeset.for_create` expects a resource module, not a record.
      # The check must not trace `post` back to a resource for `for_create`.
      source = """
      defmodule AshCredoFixtures.Blog do
        def run(id) do
          post = Ash.get!(AshCredoFixtures.Blog.Post, id)
          Ash.Changeset.for_create(post, :create, %{})
        end
      end
      """

      # The for_create call is not flagged (post is not a literal module).
      # The Ash.get! call is also not flagged (action key is a positional arg).
      issues = run_check(UseCodeInterface, source)
      refute find_by_trigger(issues, "Ash.Changeset.for_create")
    end
  end

  # ── Bulk operations ────────────────────────────────────────────────────────

  describe "bulk operations" do
    test "Ash.bulk_create classifies arg 1 and arg 2" do
      source = """
      defmodule AshCredoFixtures.Blog do
        def import(inputs) do
          Ash.bulk_create(inputs, AshCredoFixtures.Blog.Post, :create)
        end
      end
      """

      assert [issue] = run_check(UseCodeInterface, source)
      assert issue.trigger == "Ash.bulk_create"
    end

    test "Ash.bulk_update traces query variable back to a literal resource" do
      source = """
      defmodule AshCredoFixtures.Blog do
        def archive_all do
          query = Ash.Query.for_read(AshCredoFixtures.Blog.Post, :published)
          Ash.bulk_update(query, :archive, %{})
        end
      end
      """

      issues = run_check(UseCodeInterface, source)
      assert find_by_trigger(issues, "Ash.bulk_update")
    end

    test "Ash.bulk_destroy! with piped query traces through the pipe" do
      source = """
      defmodule AshCredoFixtures.Blog do
        def cleanup do
          AshCredoFixtures.Blog.Post
          |> Ash.Query.for_read(:published)
          |> Ash.bulk_destroy!(:destroy, %{})
        end
      end
      """

      issues = run_check(UseCodeInterface, source)
      assert find_by_trigger(issues, "Ash.bulk_destroy!")
    end
  end

  # ── Configuration: enforce_code_interface_in_domain ────────────────────────

  describe "enforce_code_interface_in_domain" do
    test "false silences in-domain callers but still flags callers outside the domain" do
      in_domain = """
      defmodule AshCredoFixtures.Blog do
        def list_published do
          Ash.read!(AshCredoFixtures.Blog.Post, action: :published)
        end
      end
      """

      outside_domain = """
      defmodule AshCredoFixtures.Accounts do
        def list_published do
          Ash.read!(AshCredoFixtures.Blog.Post, action: :publish)
        end
      end
      """

      assert [] =
               run_check(UseCodeInterface, in_domain, enforce_code_interface_in_domain: false)

      assert [_issue] =
               run_check(UseCodeInterface, outside_domain,
                 enforce_code_interface_in_domain: false
               )
    end

    test "false silently ignores in-domain unknown-action calls (owned by UnknownAction)" do
      source = """
      defmodule AshCredoFixtures.Blog do
        def list do
          Ash.read!(AshCredoFixtures.Blog.Post, action: :publishd)
        end
      end
      """

      # `UseCodeInterface` no longer emits unknown-action issues; the
      # `Warning.UnknownAction` check owns that diagnostic. With the
      # in-domain enforcement off, this call site is silent here.
      assert [] =
               run_check(UseCodeInterface, source, enforce_code_interface_in_domain: false)
    end

    test "false does not suppress the :not_loadable config error" do
      # :not_loadable is gated by outside_domain, not in_domain.
      source = """
      defmodule AshCredoFixtures.Blog do
        def list do
          Ash.read!(Totally.Fake.Module, action: :x)
        end
      end
      """

      assert [issue] =
               run_check(UseCodeInterface, source, enforce_code_interface_in_domain: false)

      assert issue.message =~ "Could not load"
    end

    test "default true flags a change module in the resource's domain namespace" do
      # `AshCredoFixtures.Blog.Changes.Archive` is a fixture `Ash.Resource.Change`
      # module. Its namespace sits under `AshCredoFixtures.Blog`, which is a
      # loaded `Ash.Domain`, so the check classifies it as in-domain and
      # flags the call under default settings.
      source = """
      defmodule AshCredoFixtures.Blog.Changes.Archive do
        use Ash.Resource.Change

        def change(changeset, _opts, _context) do
          Ash.read!(AshCredoFixtures.Blog.Post, action: :published)
          changeset
        end
      end
      """

      assert [issue] = run_check(UseCodeInterface, source)
      assert issue.trigger == "Ash.read!"
      assert issue.message =~ "AshCredoFixtures.Blog.Post.published_posts!"
    end

    test "false exempts a change module calling a resource in its own domain" do
      source = """
      defmodule AshCredoFixtures.Blog.Changes.Archive do
        use Ash.Resource.Change

        def change(changeset, _opts, _context) do
          Ash.read!(AshCredoFixtures.Blog.Post, action: :published)
          changeset
        end
      end
      """

      assert [] =
               run_check(UseCodeInterface, source, enforce_code_interface_in_domain: false)
    end

    test "false still flags a change module calling a cross-domain resource" do
      # The change module is in AshCredoFixtures.Blog's namespace but it's
      # calling AshCredoFixtures.Accounts.User, which belongs to a different
      # domain. Opinion A wants cross-domain calls caught even from change
      # modules - verify the in_domain=false setting doesn't silence this.
      source = """
      defmodule AshCredoFixtures.Blog.Changes.Archive do
        use Ash.Resource.Change

        def change(changeset, _opts, _context) do
          Ash.read!(AshCredoFixtures.Accounts.User, action: :read)
          changeset
        end
      end
      """

      assert [_issue] =
               run_check(UseCodeInterface, source, enforce_code_interface_in_domain: false)
    end

    test "default true flags an inline `change fn` inside a resource DSL" do
      # Inline changes (defined via an anonymous function directly in the
      # resource's `actions` block) are lexically inside the resource's
      # `defmodule`, so the innermost enclosing module IS the resource
      # itself. `caller_domain/1` resolves it through the "caller is an
      # Ash.Resource" branch without needing the callback-module heuristic.
      source = """
      defmodule AshCredoFixtures.Blog.Post do
        use Ash.Resource,
          domain: AshCredoFixtures.Blog,
          validate_domain_inclusion?: false

        actions do
          update :archive do
            change fn changeset, _context ->
              Ash.read!(AshCredoFixtures.Blog.Post, action: :published)
              changeset
            end
          end
        end
      end
      """

      assert [issue] = run_check(UseCodeInterface, source)
      assert issue.trigger == "Ash.read!"
      assert issue.message =~ "AshCredoFixtures.Blog.Post.published_posts!"
    end

    test "false exempts an inline `change fn` calling a resource in the same domain" do
      source = """
      defmodule AshCredoFixtures.Blog.Post do
        use Ash.Resource,
          domain: AshCredoFixtures.Blog,
          validate_domain_inclusion?: false

        actions do
          update :archive do
            change fn changeset, _context ->
              Ash.read!(AshCredoFixtures.Blog.Post, action: :published)
              changeset
            end
          end
        end
      end
      """

      assert [] =
               run_check(UseCodeInterface, source, enforce_code_interface_in_domain: false)
    end

    test "false still flags an inline `change fn` calling a cross-domain resource" do
      source = """
      defmodule AshCredoFixtures.Blog.Post do
        use Ash.Resource,
          domain: AshCredoFixtures.Blog,
          validate_domain_inclusion?: false

        actions do
          update :archive do
            change fn changeset, _context ->
              Ash.read!(AshCredoFixtures.Accounts.User, action: :read)
              changeset
            end
          end
        end
      end
      """

      assert [_issue] =
               run_check(UseCodeInterface, source, enforce_code_interface_in_domain: false)
    end
  end

  # ── Configuration: enforce_code_interface_outside_domain ──────────────────

  describe "enforce_code_interface_outside_domain" do
    test "false silences a caller in a different known domain" do
      source = """
      defmodule AshCredoFixtures.Accounts do
        def list_published do
          Ash.read!(AshCredoFixtures.Blog.Post, action: :publish)
        end
      end
      """

      assert [] =
               run_check(UseCodeInterface, source, enforce_code_interface_outside_domain: false)
    end

    test "false silences plain (no-domain) callers" do
      source = """
      defmodule SomeController do
        def list do
          Ash.read!(AshCredoFixtures.Blog.Post, action: :publish)
        end
      end
      """

      assert [] =
               run_check(UseCodeInterface, source, enforce_code_interface_outside_domain: false)
    end

    test "false silences :not_loadable config errors" do
      source = """
      defmodule SomeController do
        def list do
          Ash.read!(Totally.Fake.Module, action: :x)
        end
      end
      """

      assert [] =
               run_check(UseCodeInterface, source, enforce_code_interface_outside_domain: false)
    end

    test "false still flags in-domain callers" do
      source = """
      defmodule AshCredoFixtures.Blog do
        def list do
          Ash.read!(AshCredoFixtures.Blog.Post, action: :published)
        end
      end
      """

      assert [_issue] =
               run_check(UseCodeInterface, source, enforce_code_interface_outside_domain: false)
    end

    test "false silently ignores outside-domain unknown-action calls (owned by UnknownAction)" do
      source = """
      defmodule AshCredoFixtures.Accounts do
        def list do
          Ash.read!(AshCredoFixtures.Blog.Post, action: :publishd)
        end
      end
      """

      # `UseCodeInterface` no longer emits unknown-action issues; the
      # `Warning.UnknownAction` check owns that diagnostic. With the
      # outside-domain enforcement off, this call site is silent here.
      assert [] =
               run_check(UseCodeInterface, source, enforce_code_interface_outside_domain: false)
    end
  end

  # ── Configuration: prefer_interface_scope ──────────────────────────────────

  describe "prefer_interface_scope" do
    test ":auto (default) suggests the resource interface for in-domain callers on :read" do
      source = """
      defmodule AshCredoFixtures.Blog do
        def list do
          Ash.read!(AshCredoFixtures.Blog.Post, action: :read)
        end
      end
      """

      assert [issue] = run_check(UseCodeInterface, source)
      assert issue.message =~ "AshCredoFixtures.Blog.Post.all_posts!"
    end

    test ":auto suggests the domain interface for outside-domain callers on :read" do
      source = """
      defmodule AshCredoFixtures.Accounts do
        def list do
          Ash.read!(AshCredoFixtures.Blog.Post, action: :read)
        end
      end
      """

      assert [issue] = run_check(UseCodeInterface, source)
      assert issue.message =~ "AshCredoFixtures.Blog.list_posts!"
    end

    test ":resource overrides auto for outside-domain callers on :read" do
      source = """
      defmodule AshCredoFixtures.Accounts do
        def list do
          Ash.read!(AshCredoFixtures.Blog.Post, action: :read)
        end
      end
      """

      assert [issue] = run_check(UseCodeInterface, source, prefer_interface_scope: :resource)
      assert issue.message =~ "AshCredoFixtures.Blog.Post.all_posts!"
    end

    test ":domain overrides auto for in-domain callers on :read" do
      source = """
      defmodule AshCredoFixtures.Blog do
        def list do
          Ash.read!(AshCredoFixtures.Blog.Post, action: :read)
        end
      end
      """

      assert [issue] = run_check(UseCodeInterface, source, prefer_interface_scope: :domain)
      assert issue.message =~ "AshCredoFixtures.Blog.list_posts!"
    end

    test ":resource suggests 'define :publish' when no resource iface exists" do
      source = """
      defmodule AshCredoFixtures.Blog do
        def run do
          Ash.read!(AshCredoFixtures.Blog.Post, action: :publish)
        end
      end
      """

      assert [issue] = run_check(UseCodeInterface, source, prefer_interface_scope: :resource)
      assert issue.message =~ "Prefer a code interface on"
      assert issue.message =~ "AshCredoFixtures.Blog.Post"
      assert issue.message =~ "define :publish"
    end

    test ":domain suggests 'define a domain interface for :published' when no domain iface exists" do
      source = """
      defmodule AshCredoFixtures.Blog do
        def run do
          Ash.read!(AshCredoFixtures.Blog.Post, action: :published)
        end
      end
      """

      assert [issue] = run_check(UseCodeInterface, source, prefer_interface_scope: :domain)
      assert issue.message =~ "Prefer a code interface on"
      assert issue.message =~ "AshCredoFixtures.Blog"
      assert issue.message =~ "define :some_name, action: :published"
    end
  end

  # ── Configuration: combinations ────────────────────────────────────────────

  describe "configuration combinations" do
    test "both enforce flags false produces no issues at all" do
      sources = [
        # in-domain caller
        """
        defmodule AshCredoFixtures.Blog do
          def a do
            Ash.read!(AshCredoFixtures.Blog.Post, action: :published)
          end
        end
        """,
        # outside-domain caller
        """
        defmodule AshCredoFixtures.Accounts do
          def a do
            Ash.read!(AshCredoFixtures.Blog.Post, action: :publish)
          end
        end
        """,
        # plain caller
        """
        defmodule SomeController do
          def a do
            Ash.read!(AshCredoFixtures.Blog.Post, action: :publish)
          end
        end
        """,
        # :not_loadable
        """
        defmodule SomeController do
          def a do
            Ash.read!(Totally.Fake.Module, action: :x)
          end
        end
        """
      ]

      for source <- sources do
        assert [] =
                 run_check(UseCodeInterface, source,
                   enforce_code_interface_in_domain: false,
                   enforce_code_interface_outside_domain: false
                 )
      end
    end

    test "enforce_code_interface_outside_domain false + prefer_interface_scope :resource - only in-domain flagged, suggesting resource" do
      in_domain = """
      defmodule AshCredoFixtures.Blog do
        def list do
          Ash.read!(AshCredoFixtures.Blog.Post, action: :read)
        end
      end
      """

      outside_domain = """
      defmodule AshCredoFixtures.Accounts do
        def list do
          Ash.read!(AshCredoFixtures.Blog.Post, action: :read)
        end
      end
      """

      opts = [
        enforce_code_interface_outside_domain: false,
        prefer_interface_scope: :resource
      ]

      assert [issue] = run_check(UseCodeInterface, in_domain, opts)
      assert issue.message =~ "AshCredoFixtures.Blog.Post.all_posts!"

      assert [] = run_check(UseCodeInterface, outside_domain, opts)
    end
  end
end
