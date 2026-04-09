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
  """

  use Ash.Resource,
    domain: AshCredoFixtures.Blog,
    validate_domain_inclusion?: false

  code_interface do
    define :archive
    define :published_posts, action: :published
    define :all_posts, action: :read
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
    resource AshCredoFixtures.Blog.Tag
    resource AshCredoFixtures.Blog.Empty
    resource AshCredoFixtures.Blog.WithAuthorizer
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

defmodule AshCredoFixtures.Blog.Tag do
  @moduledoc """
  Resource with multiple `:create` actions and no `primary?: true`. Ash
  emits a verification warning but compiles the module, so we can
  introspect it via `Ash.Resource.Info.actions/1` for the
  `Design.MissingPrimaryAction` failure-path test.
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
