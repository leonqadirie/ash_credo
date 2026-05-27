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
    resource AshCredoFixtures.Blog.CustomTimestamps
    resource AshCredoFixtures.Blog.Tag
    resource AshCredoFixtures.Blog.GenericActions
    resource AshCredoFixtures.Blog.Empty
    resource AshCredoFixtures.Blog.WithAuthorizer
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

defmodule AshCredoFixtures.Accounts do
  @moduledoc "Fixture domain for cross-domain tests."

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshCredoFixtures.Accounts.User
    resource AshCredoFixtures.Accounts.Member
    resource AshCredoFixtures.Accounts.Profile
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

defmodule AshCredoFixtures.Blog.Empty do
  @moduledoc """
  `NoActions` failure-path fixture: has a (default) data layer but no `actions`
  block at all. Compiles fine - Ash does not require actions.
  """

  use Ash.Resource,
    domain: AshCredoFixtures.Blog,
    validate_domain_inclusion?: false

  attributes do
    uuid_primary_key :id
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

defmodule AshCredoFixtures.NoPrimaryKey do
  @moduledoc """
  `MissingPrimaryKey` failure-path fixture: a resource with no primary key at
  all. Ash permits this (read-only / manual resources legitimately lack one),
  so the module compiles and `Ash.Resource.Info.primary_key/1` returns `[]`.
  """

  use Ash.Resource,
    domain: AshCredoFixtures.Blog,
    validate_domain_inclusion?: false

  attributes do
    attribute :title, :string, public?: true
  end
end

defmodule AshCredoFixtures.Blog.PostTagFragment do
  @moduledoc """
  `MissingPrimaryKey` regression fixture for fragment-supplied primary keys
  (issue #133). A `Spark.Dsl.Fragment` that contributes a composite primary
  key via two `belongs_to ..., primary_key?: true` relationships. The PK is
  invisible to AST scanning of the composing resource but present in
  `Ash.Resource.Info.primary_key/1`.
  """

  use Spark.Dsl.Fragment, of: Ash.Resource

  relationships do
    belongs_to :post, AshCredoFixtures.Blog.Post do
      primary_key? true
      allow_nil? false
    end

    belongs_to :tag, AshCredoFixtures.Blog.Tag do
      primary_key? true
      allow_nil? false
    end
  end
end

defmodule AshCredoFixtures.Blog.PostTag do
  @moduledoc """
  `MissingPrimaryKey` happy-path fixture: a join resource whose composite
  primary key is supplied entirely by `AshCredoFixtures.Blog.PostTagFragment`.
  Its own body declares no primary key, so an AST-only check would flag it -
  the compiled check must not.
  """

  use Ash.Resource,
    domain: AshCredoFixtures.Blog,
    validate_domain_inclusion?: false,
    fragments: [AshCredoFixtures.Blog.PostTagFragment]

  actions do
    defaults [:read]
    default_accept []
  end
end

defmodule AshCredoFixtures.OptOutPrimaryKey do
  @moduledoc """
  `MissingPrimaryKey` happy-path fixture for the `require_primary_key? false`
  opt-out (Ash verifier branch 3). It has a field and no primary key, so
  `Ash.Resource.Info.primary_key/1` returns `[]`, but the explicit opt-out
  means Ash raises nothing - the check must not flag it.
  """

  use Ash.Resource,
    domain: AshCredoFixtures.Blog,
    validate_domain_inclusion?: false

  resource do
    require_primary_key? false
  end

  attributes do
    attribute :title, :string, public?: true
  end
end

defmodule AshCredoFixtures.GenericOnlyNoFields do
  @moduledoc """
  `MissingPrimaryKey` happy-path fixture for the generic-only/no-fields
  exemption (Ash verifier branch 4): a resource whose only action is generic
  and which declares no fields, so Ash does not require a primary key.
  """

  use Ash.Resource,
    domain: AshCredoFixtures.Blog,
    validate_domain_inclusion?: false

  actions do
    action :ping do
      run fn _input, _ -> :ok end
    end
  end
end
