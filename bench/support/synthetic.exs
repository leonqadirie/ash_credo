defmodule Bench.Synthetic do
  @moduledoc """
  Generates deterministic Ash source code for the benchmarks.

  Every size is a pure function of its parameters, so `main` and a branch
  benchmark identical input. The resources are never compiled: AST checks
  find matches in them and compiled checks skip them. The trailing caller
  module calls the compiled `AshCredoFixtures` modules, so the compiled
  call-site checks resolve real actions and code interfaces.
  """

  @sizes %{small: {1, 10}, medium: {8, 80}, large: {60, 600}}

  def sizes, do: [:small, :medium, :large]

  def source(size) do
    {resources, calls} = Map.fetch!(@sizes, size)

    Enum.join(
      [domain(resources), empty_domain()] ++
        Enum.map(1..resources, &resource/1) ++ [caller(calls)],
      "\n"
    )
  end

  defp domain(resources) do
    entries = Enum.map_join(1..resources, "\n", &"    resource Bench.Synthetic.R#{&1}")

    """
    defmodule Bench.Synthetic.Domain do
      use Ash.Domain

      resources do
    #{entries}
      end
    end
    """
  end

  defp empty_domain do
    """
    defmodule Bench.Synthetic.EmptyDomain do
      use Ash.Domain

      resources do
      end
    end
    """
  end

  # Every fourth resource omits `domain:` so MissingDomain has work. Field
  # counts vary with the index; every twentieth resource exceeds
  # LargeResource's 400-line default.
  defp resource(i) do
    fields = if rem(i, 20) == 0, do: 60, else: 4 + rem(i, 6)
    domain = if rem(i, 4) == 0, do: "", else: "\n    domain: Bench.Synthetic.Domain,"

    """
    defmodule Bench.Synthetic.R#{i} do
      use Ash.Resource,#{domain}
        authorizers: [Ash.Policy.Authorizer]

      attributes do
        uuid_primary_key :id
    #{Enum.map_join(1..fields, "\n", &attribute/1)}
        attribute :hashed_password, :string, public?: true
        attribute :inserted_on, :utc_datetime, default: DateTime.utc_now()
      end

      relationships do
        belongs_to :owner, Bench.Synthetic.R#{max(i - 1, 1)}
        has_many :children, Bench.Synthetic.R#{i + 1}, destination_attribute: :owner_id
      end

      calculations do
    #{Enum.map_join(1..fields, "\n", &calculation/1)}
        calculate :recent?, :boolean, expr(inserted_on > ^DateTime.utc_now())
      end

      actions do
        defaults [:read, :destroy]

        create :create do
          accept :*
        end

    #{Enum.map_join(1..fields, "\n", &update_action/1)}

        read :visible do
          description "Rows visible to the actor."
          prepare fn query, _context -> query end
        end
      end

      policies do
        policy always() do
          authorize_if always()
        end
      end

      def visible_rows do
        require Ash.Query
        __MODULE__ |> Ash.Query.filter(field_1 != nil) |> Ash.read!()
      end

      def admin_rows(actor) do
        Ash.read!(__MODULE__, actor: actor, authorize?: false)
      end
    end

    defmodule Bench.Synthetic.R#{i}.Changes.Touch do
      use Ash.Resource.Change

      def change(changeset, _opts, _context) do
        Bench.Synthetic.Repo.query!("UPDATE r#{i} SET touched = true", [])
        changeset
      end
    end
    """
  end

  defp attribute(j) do
    if rem(j, 2) == 0 do
      "    attribute :field_#{j}, :string, allow_nil?: false, public?: true"
    else
      "    attribute :field_#{j}, :string"
    end
  end

  defp calculation(j), do: ~s|    calculate :label_#{j}, :string, expr(field_#{j} <> "!")|

  defp update_action(j) do
    """
        update :set_field_#{j} do
          accept [:field_#{j}, :is_admin]
          change fn changeset, _context -> changeset end
        end
    """
  end

  # Mixes valid, unknown, and interface-shadowed calls against the compiled
  # fixtures; `Ash.Query.filter/2` without `require Ash.Query` feeds
  # MissingMacroDirective.
  defp caller(calls) do
    """
    defmodule Bench.Synthetic.Caller do
      alias AshCredoFixtures.Blog.Post

    #{Enum.map_join(1..calls, "\n", &call/1)}
    end
    """
  end

  defp call(k) do
    case rem(k, 5) do
      0 ->
        """
          def call_#{k}(actor) do
            Post |> Ash.Query.for_read(:published) |> Ash.read!(actor: actor)
          end
        """

      1 ->
        """
          def call_#{k}(post) do
            post |> Ash.Changeset.for_update(:archive) |> Ash.update!()
          end
        """

      2 ->
        """
          def call_#{k}(actor) do
            Ash.read!(Post, action: :missing_#{k}, actor: actor)
          end
        """

      3 ->
        """
          def call_#{k}(id) do
            Post |> Ash.Query.filter(id == ^id) |> Ash.read_one()
          end
        """

      4 ->
        """
          def call_#{k} do
            AshCredoFixtures.Blog.list_posts!()
          end
        """
    end
  end
end
