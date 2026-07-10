defmodule AshCredoFixtures.CustomTimestampType do
  @moduledoc """
  A custom Ash NewType that is a subtype of `:utc_datetime_usec` but overrides
  `storage_type` to return a DB-specific atom. Mimics
  `AshPostgres.TimestamptzUsec` for testing `MissingTimestamps` with custom
  timestamp types whose module name does not contain "datetime" and whose
  `storage_type` is not in the standard set.
  """

  use Ash.Type.NewType, subtype_of: :utc_datetime_usec

  @impl true
  def storage_type(_), do: :"timestamptz(6)"
end

defmodule AshCredoFixtures.Blog.Post do
  @moduledoc """
  Fixture resource used by `UseCodeInterface` tests. Intentionally covers
  every classification variant the check needs to exercise:

    * `:archive` - resource-level interface, name == action name.
    * `:published` - resource-level interface, name differs (`published_posts`).
    * `:publish` - only a **domain**-level interface exists (`publish_post`).
    * `:draft`   - action exists, no interface anywhere.
    * `:read`    - default action, BOTH a resource-level (`all_posts`) AND a
      domain-level (`list_posts`) interface - used to exercise
      `prefer_interface_scope` overrides.
    * `:read`    - get-by-id resource interface (`get_post_by_id`) used to
      ensure `Ash.get!` suggestions do not point at list-returning helpers.
  """

  use Ash.Resource,
    domain: AshCredoFixtures.Blog,
    validate_domain_inclusion?: false

  code_interface do
    define :archive
    define :published_posts, action: :published
    define :all_posts, action: :read
    define :get_post_by_id, action: :read, get_by: [:id]
  end

  actions do
    defaults [:create, :update, :destroy]
    default_accept []

    read :read, primary?: true
    read :published, primary?: false
    read :draft, primary?: false

    update :archive, primary?: false
    update :publish, primary?: false
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
  end
end

defmodule AshCredoFixtures.Blog do
  @moduledoc """
  Fixture domain hosting `AshCredoFixtures.Blog.Post`. Defines a couple of
  domain-level code interfaces to exercise cross-domain message variants.
  """

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshCredoFixtures.Blog.Post do
      define :list_posts, action: :read
      define :publish_post, action: :publish
    end

    resource AshCredoFixtures.Blog.Article
    resource AshCredoFixtures.Blog.PartialTimestamps
    resource AshCredoFixtures.Blog.CreateOnlyTimestamp
    resource AshCredoFixtures.Blog.CustomTimestamps
    resource AshCredoFixtures.Blog.Tag
    resource AshCredoFixtures.Blog.Contact
    resource AshCredoFixtures.Blog.GenericActions
    resource AshCredoFixtures.Blog.WithAuthorizer
    resource AshCredoFixtures.Blog.WithAuthorizerAndPolicies
    resource AshCredoFixtures.Blog.WithCalcInterface
  end
end

defmodule AshCredoFixtures.Accounts.User do
  @moduledoc "Fixture resource in a different domain for cross-domain tests."

  use Ash.Resource,
    domain: AshCredoFixtures.Accounts,
    validate_domain_inclusion?: false

  actions do
    defaults [:create, :read, :update, :destroy]
    default_accept []
  end

  attributes do
    uuid_primary_key :id
    attribute :email, :string, public?: true
  end
end

defmodule AshCredoFixtures.Accounts.Member do
  @moduledoc """
  `MissingIdentity` failure-path fixture: has `:email` and `:username` attributes
  but no identity covering either of them.
  """

  use Ash.Resource,
    domain: AshCredoFixtures.Accounts,
    validate_domain_inclusion?: false

  actions do
    defaults [:read]
    default_accept []
  end

  attributes do
    uuid_primary_key :id
    attribute :email, :string, public?: true
    attribute :username, :string, public?: true
  end
end

defmodule AshCredoFixtures.Accounts.Profile do
  @moduledoc """
  `MissingIdentity` happy-path fixture: has `:email` attribute AND an
  `:unique_email` identity covering it.
  """

  use Ash.Resource,
    domain: AshCredoFixtures.Accounts,
    validate_domain_inclusion?: false

  actions do
    defaults [:read]
    default_accept []
  end

  attributes do
    uuid_primary_key :id
    attribute :email, :string, public?: true
  end

  identities do
    identity :unique_email, [:email]
  end
end

defmodule AshCredoFixtures.Accounts.EmailKey do
  @moduledoc """
  `MissingIdentity` sole-primary-key fixture: `:email` IS the primary key,
  so it is already unique and an identity would be redundant.
  """

  use Ash.Resource,
    domain: AshCredoFixtures.Accounts,
    validate_domain_inclusion?: false

  actions do
    defaults [:read]
    default_accept []
  end

  attributes do
    attribute :email, :string, primary_key?: true, allow_nil?: false, public?: true
  end
end

defmodule AshCredoFixtures.Accounts.TenantEmailKey do
  @moduledoc """
  `MissingIdentity` composite-primary-key fixture: `:email` is one member
  of a composite key - only the tuple is unique, so the identity
  suggestion still applies to the attribute.
  """

  use Ash.Resource,
    domain: AshCredoFixtures.Accounts,
    validate_domain_inclusion?: false

  actions do
    defaults [:read]
    default_accept []
  end

  attributes do
    attribute :tenant_id, :uuid, primary_key?: true, allow_nil?: false, public?: true
    attribute :email, :string, primary_key?: true, allow_nil?: false, public?: true
  end
end

defmodule AshCredoFixtures.Accounts.EmbeddedContact do
  @moduledoc """
  `MissingIdentity` embedded-resource fixture: declares `data_layer: :embedded`
  and an `:email` attribute with no covering identity. Identities on embedded
  resources are silently ignored by Ash (the `Ash.DataLayer.Simple` data layer
  has no identity enforcement), so the check must skip them.
  """

  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :email, :string, public?: true
  end
end

defmodule AshCredoFixtures.Accounts.Account do
  @moduledoc """
  `UseCodeInterface` fixture for the long-tail suggestion families:

    * `get_account_by_email` uses `get_by_identity: :unique_email` - the
      suggestion must resolve the identity to its keys to match a
      `Ash.get!(Account, %{email: ...})` lookup.
    * `get_account_by_action` covers an identity whose key is literally
      `:action`, which must not be confused with `Ash.get/3` call options.
    * `fetch_account_by_id` sets `not_found_error?: false` - the suggested
      call must NOT carry the trailing `not_found_error?: false` argument.
    * `single_account` is a no-key `get?: true` interface suitable for
      replacing `Ash.read_one`, but not `Ash.read_first`.
    * `action_single_account` targets a read action whose own `get?: true`
      makes the otherwise plain interface return one record.
    * `:activate` is a generic action with an interface - builder calls via
      `Ash.ActionInput.for_action/3` must suggest the `input_to_*` helper.
  """

  use Ash.Resource,
    domain: AshCredoFixtures.Accounts,
    validate_domain_inclusion?: false

  code_interface do
    define :get_account_by_email, action: :read, get_by_identity: :unique_email
    define :get_account_by_action, action: :read, get_by_identity: :unique_action
    define :fetch_account_by_id, action: :read, get_by: [:id], not_found_error?: false
    define :single_account, action: :read, get?: true, not_found_error?: false
    define :action_single_account, action: :singleton
    define :activate
  end

  actions do
    defaults [:read]
    default_accept []

    read :singleton, get?: true

    action :activate do
      run fn _input, _ -> :ok end
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :email, :string, public?: true
    attribute :action, :string, public?: true
  end

  identities do
    identity :unique_email, [:email]
    identity :unique_action, [:action]
  end
end

defmodule AshCredoFixtures.Standalone do
  @moduledoc """
  Resource without a domain: `UseCodeInterface` has no domain interface to
  point at, so both the `:auto` and the `prefer_interface_scope: :domain`
  paths must fall back to suggesting a resource-level interface.
  """

  use Ash.Resource, domain: nil, validate_domain_inclusion?: false

  actions do
    defaults [:read]
    default_accept []
  end

  attributes do
    uuid_primary_key :id
  end
end

defmodule AshCredoFixtures.Accounts do
  @moduledoc "Fixture domain for cross-domain tests."

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshCredoFixtures.Accounts.User
    resource AshCredoFixtures.Accounts.Member
    resource AshCredoFixtures.Accounts.Profile
    resource AshCredoFixtures.Accounts.Account
    resource AshCredoFixtures.Accounts.EmailKey
    resource AshCredoFixtures.Accounts.TenantEmailKey
  end
end

defmodule AshCredoFixtures.Plain do
  @moduledoc "A non-Ash module, for `:not_a_resource` tests."

  def hello, do: :world
end

defmodule AshCredoFixtures.Blog.Changes.Archive do
  @moduledoc """
  Fixture `Ash.Resource.Change` module used to exercise the "callback module
  belongs to its namespace's domain" caller classification. Its name puts it
  under `AshCredoFixtures.Blog`, so the check should treat it as in-domain
  for `AshCredoFixtures.Blog` resources and outside-domain for everything else.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context), do: changeset
end

defmodule AshCredoFixtures.Blog.Article do
  @moduledoc """
  Resource with timestamps via the `timestamps()` macro. Used by
  `Design.MissingTimestamps` happy-path tests (the existing `Blog.Post`
  fixture has no timestamps - that covers the failure path).
  """

  use Ash.Resource,
    domain: AshCredoFixtures.Blog,
    validate_domain_inclusion?: false

  actions do
    defaults [:read]
    default_accept []
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    timestamps()
  end
end

defmodule AshCredoFixtures.Blog.PartialTimestamps do
  @moduledoc """
  `MissingTimestamps` regression fixture: has an `update_timestamp` but no
  `create_timestamp`. Before the datetime-type filter, `:id` from
  `uuid_primary_key` (non-writable, default function) would falsely satisfy
  the create-timestamp predicate and mask the missing create timestamp.
  """

  use Ash.Resource,
    domain: AshCredoFixtures.Blog,
    validate_domain_inclusion?: false

  actions do
    defaults [:read]
    default_accept []
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    update_timestamp :updated_at
  end
end

defmodule AshCredoFixtures.Blog.CreateOnlyTimestamp do
  @moduledoc """
  `MissingTimestamps` fixture with only a `create_timestamp`: the check
  must name the missing update side.
  """

  use Ash.Resource,
    domain: AshCredoFixtures.Blog,
    validate_domain_inclusion?: false

  actions do
    defaults [:read]
    default_accept []
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    create_timestamp :inserted_at
  end
end

defmodule AshCredoFixtures.Blog.CustomTimestamps do
  @moduledoc """
  `MissingTimestamps` happy-path fixture: uses a custom timestamp type
  (`AshCredoFixtures.CustomTimestampType`) whose module name does not contain
  "datetime". Exercises the `Ash.Type.storage_type/2` resolution path.
  """

  use Ash.Resource,
    domain: AshCredoFixtures.Blog,
    validate_domain_inclusion?: false

  actions do
    defaults [:read]
    default_accept []
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    create_timestamp :inserted_at, type: AshCredoFixtures.CustomTimestampType
    update_timestamp :updated_at, type: AshCredoFixtures.CustomTimestampType
  end
end

defmodule AshCredoFixtures.Blog.WithAuthorizer do
  @moduledoc """
  `AuthorizerWithoutPolicies` failure-path fixture: declares
  `Ash.Policy.Authorizer` but does not define a `policies` block. Compiles
  fine - empty policies list is a runtime concern, not a compile error.
  """

  use Ash.Resource,
    domain: AshCredoFixtures.Blog,
    validate_domain_inclusion?: false,
    authorizers: [Ash.Policy.Authorizer]

  actions do
    defaults [:read]
    default_accept []
  end

  attributes do
    uuid_primary_key :id
  end
end

defmodule AshCredoFixtures.Blog.WithAuthorizerAndPolicies do
  @moduledoc """
  `AuthorizerWithoutPolicies` happy-path fixture: declares
  `Ash.Policy.Authorizer` AND defines a non-empty `policies` block, so the
  check must stay silent.
  """

  use Ash.Resource,
    domain: AshCredoFixtures.Blog,
    validate_domain_inclusion?: false,
    authorizers: [Ash.Policy.Authorizer]

  policies do
    policy always() do
      authorize_if always()
    end
  end

  actions do
    defaults [:read]
    default_accept []
  end

  attributes do
    uuid_primary_key :id
  end
end

defmodule AshCredoFixtures.Blog.WithCalcInterface do
  @moduledoc """
  Fixture resource with a calculation code interface, used by
  `Refactor.RaisingCall` tests to verify that calculation-interface bang
  variants (`upcased_title!`) are flagged alongside regular code-interface
  bangs.
  """

  use Ash.Resource,
    domain: AshCredoFixtures.Blog,
    validate_domain_inclusion?: false

  code_interface do
    define_calculation :upcased_title
  end

  actions do
    defaults [:read]
    default_accept []
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
  end

  calculations do
    calculate :upcased_title, :string, expr(fragment("upper(?)", title))
  end
end

defmodule AshCredoFixtures.Blog.Tag do
  @moduledoc """
  Resource with multiple `:create` actions and no `primary?: true`. Ash
  compiles this without any error or warning - a missing primary action
  only fails at runtime - so we can introspect it via
  `Ash.Resource.Info.actions/1` for the `Design.MissingPrimaryAction`
  failure-path test.
  """

  use Ash.Resource,
    domain: AshCredoFixtures.Blog,
    validate_domain_inclusion?: false

  actions do
    default_accept []
    defaults [:read]
    create :create_basic
    create :create_with_slug
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end
end

defmodule AshCredoFixtures.Blog.Contact do
  @moduledoc """
  `RedundantValidation` fixture: `:name`, `:handle`, and `:slug` carry
  `allow_nil? false`, `:nickname` stays nullable, and the `:import` create
  action reopens `:name` (but not `:handle`) via `allow_nil_input` - the
  escape hatch under which a `present` validation is NOT redundant.
  The `:reslug` update action defines an `argument :slug` shadowing the
  attribute - there `present` validates the argument in the atomic path,
  the other escape hatch under which the validation is NOT redundant.
  The `:import_slugged` create action defines the same argument - creates
  never run atomically, so the escape must NOT apply there.
  """

  use Ash.Resource,
    domain: AshCredoFixtures.Blog,
    validate_domain_inclusion?: false

  actions do
    defaults [:read]

    create :create do
      accept [:name, :nickname]
    end

    update :rename do
      accept [:name]
    end

    create :import do
      accept [:name, :nickname]
      allow_nil_input [:name]
    end

    update :reslug do
      argument :slug, :string
      accept []
    end

    create :import_slugged do
      argument :slug, :string
      accept []
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :handle, :string, allow_nil?: false, default: "anon", public?: true
    attribute :nickname, :string, public?: true
    attribute :slug, :string, allow_nil?: false, default: "slug", public?: true
  end
end

defmodule AshCredoFixtures.Blog.GenericActions do
  @moduledoc """
  `MissingPrimaryAction` regression fixture: has multiple generic actions
  (type `:action`) and none marked `primary?: true`. Generic
  actions are never invoked implicitly - callers always name them via
  `Ash.run_action/2` - so `primary?` has no behavioral effect and the check
  must not flag them.
  """

  use Ash.Resource,
    domain: AshCredoFixtures.Blog,
    validate_domain_inclusion?: false

  actions do
    defaults [:read]
    default_accept []

    action :ping do
      run fn _input, _ -> :ok end
    end

    action :pong do
      run fn _input, _ -> :ok end
    end
  end

  attributes do
    uuid_primary_key :id
  end
end

defmodule AshCredoFixtures.FakeMacros do
  @moduledoc """
  Plain (non-Ash) fixture module with a mix of real macros and regular
  functions. Used by `Warning.MissingMacroDirective` tests to verify that
  user-supplied entries in `macro_modules` are introspected via
  `module.__info__(:macros)` and only their macros are flagged - not their
  regular functions.
  """

  defmacro do_thing(x) do
    quote do
      unquote(x)
    end
  end

  defmacro other(a, b) do
    quote do
      {unquote(a), unquote(b)}
    end
  end

  def regular(value), do: value
end
