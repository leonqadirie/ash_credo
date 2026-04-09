defmodule AshCredoFixtures.Blog.Post do
  @moduledoc """
  Fixture resource used by `UseCodeInterface` tests. Intentionally covers
  every classification variant the check needs to exercise:

    * `:archive` — resource-level interface, name == action name.
    * `:published` — resource-level interface, name differs (`published_posts`).
    * `:publish` — only a **domain**-level interface exists (`publish_post`).
    * `:draft`   — action exists, no interface anywhere.
    * `:read`    — default action, BOTH a resource-level (`all_posts`) AND a
      domain-level (`list_posts`) interface — used to exercise
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

defmodule AshCredoFixtures.Accounts do
  @moduledoc "Fixture domain for cross-domain tests."

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshCredoFixtures.Accounts.User
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
