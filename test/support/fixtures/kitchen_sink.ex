defmodule AshCredoFixtures.KitchenSink.Changes.Stamp do
  @moduledoc "Module-based change that `AshCredoFixtures.KitchenSink.Order` runs on `:place`."

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context), do: changeset
end

defmodule AshCredoFixtures.KitchenSink.Calculations.Doubled do
  @moduledoc "Module-based calculation that `AshCredoFixtures.KitchenSink.Order` declares."

  use Ash.Resource.Calculation

  @impl true
  def calculate(records, _opts, _context), do: Enum.map(records, &((&1.quantity || 0) * 2))
end

defmodule AshCredoFixtures.KitchenSink.Address do
  @moduledoc "Embedded resource that `AshCredoFixtures.KitchenSink.Order` uses as an attribute type."

  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :street, :string, public?: true
    attribute :city, :string, public?: true, allow_nil?: false
  end
end

defmodule AshCredoFixtures.KitchenSink.Customer do
  @moduledoc "Relationship target of `AshCredoFixtures.KitchenSink.Order`."

  use Ash.Resource,
    domain: AshCredoFixtures.KitchenSink,
    validate_domain_inclusion?: false,
    data_layer: Ash.DataLayer.Ets

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id
    attribute :email, :string, public?: true, allow_nil?: false, sensitive?: true
  end

  relationships do
    has_many :orders, AshCredoFixtures.KitchenSink.Order
  end

  identities do
    identity :unique_email, [:email], pre_check?: true
  end
end

defmodule AshCredoFixtures.KitchenSink.Order do
  @moduledoc """
  Resource that uses as many DSL variants as compile together: every
  action type including a generic action, arguments, changes and
  validations, sensitive and embedded attributes, timestamps,
  relationships, identities, expression and module calculations,
  aggregates, resource-level `define` and `define_calculation`, and
  policies with a bypass and field policies. The domain lists a
  `define_calculation` before its `define`s and leaves `:cancel` without
  an interface.
  """

  use Ash.Resource,
    domain: AshCredoFixtures.KitchenSink,
    validate_domain_inclusion?: false,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer]

  code_interface do
    define_calculation :quantity_doubled, calculation: :doubled, args: [{:ref, :quantity}]
    define :get_order, action: :read, get_by: [:id]
    define :get_order_by_reference, action: :read, get_by_identity: :unique_reference
    define :place, args: [:reference]
    define :ship
    define :total_for, action: :total, args: [:currency]
  end

  actions do
    default_accept [:quantity]
    defaults [:destroy]

    read :read do
      primary? true
      pagination offset?: true, required?: false
    end

    read :by_reference do
      get? true
      argument :reference, :string, allow_nil?: false
      filter expr(reference == ^arg(:reference))
    end

    create :place do
      primary? true
      accept [:reference, :quantity, :address, :customer_id]
      argument :note, :string, sensitive?: true
      change set_attribute(:status, :placed)
      change AshCredoFixtures.KitchenSink.Changes.Stamp
      validate present(:reference)
      validate compare(:quantity, greater_than: 0)
    end

    update :ship do
      primary? true
      accept []
      require_atomic? false
      change set_attribute(:status, :shipped)
      validate attribute_equals(:status, :placed)
    end

    update :cancel do
      accept []
      change set_attribute(:status, :cancelled)
    end

    action :total, :decimal do
      argument :currency, :string, allow_nil?: false
      run fn _input, _context -> {:ok, Decimal.new(0)} end
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :reference, :string, public?: true, allow_nil?: false
    attribute :quantity, :integer, public?: true, default: 1
    attribute :secret_code, :string, sensitive?: true

    attribute :status, :atom,
      public?: true,
      constraints: [one_of: [:draft, :placed, :shipped, :cancelled]],
      default: :draft

    attribute :address, AshCredoFixtures.KitchenSink.Address, public?: true
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :customer, AshCredoFixtures.KitchenSink.Customer, public?: true
  end

  identities do
    identity :unique_reference, [:reference], pre_check?: true
  end

  calculations do
    calculate :doubled, :integer, expr(quantity * 2) do
      allow_nil? false
    end

    calculate :doubled_in_elixir, :integer, AshCredoFixtures.KitchenSink.Calculations.Doubled
  end

  aggregates do
    count :sibling_order_count, [:customer, :orders]
  end

  policies do
    bypass actor_attribute_equals(:admin?, true) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if relates_to_actor_via(:customer)
    end

    policy action_type([:create, :update, :destroy]) do
      forbid_unless actor_present()
      authorize_if always()
    end

    policy action(:total) do
      authorize_if always()
    end
  end

  field_policies do
    field_policy :status do
      forbid_if always()
    end

    field_policy :* do
      authorize_if always()
    end
  end
end

defmodule AshCredoFixtures.KitchenSink do
  @moduledoc "Domain for the kitchen-sink fixtures; see `AshCredoFixtures.KitchenSink.Order`."

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshCredoFixtures.KitchenSink.Order do
      define_calculation :order_quantity_doubled,
        calculation: :doubled,
        args: [{:ref, :quantity}]

      define :list_orders, action: :read
      define :place_order, action: :place, args: [:reference]
      define :order_total, action: :total, args: [:currency]
    end

    resource AshCredoFixtures.KitchenSink.Customer
  end
end
