defmodule AshCredo.IntrospectionTest do
  use AshCredo.CheckCase

  alias AshCredo.Introspection

  @ash_resource """
  defmodule MyApp.Post do
    use Ash.Resource, domain: MyApp.Blog

    attributes do
      uuid_primary_key :id
      attribute :title, :string, public?: true
      attribute :body, :string
      timestamps()
    end

    actions do
      defaults [:read, :destroy]

      create :create do
        primary? true
        accept [:title, :body]
      end
    end
  end
  """

  @ash_domain """
  defmodule MyApp.Blog do
    use Ash.Domain

    resources do
      resource MyApp.Post
    end
  end
  """

  @plain_module """
  defmodule MyApp.Utils do
    def hello, do: :world
  end
  """

  describe "ash_resource?/1" do
    test "returns true for Ash.Resource modules" do
      assert Introspection.ash_resource?(source_file(@ash_resource))
    end

    test "returns false for non-Ash modules" do
      refute Introspection.ash_resource?(source_file(@plain_module))
    end

    test "returns false for Ash.Domain modules" do
      refute Introspection.ash_resource?(source_file(@ash_domain))
    end
  end

  describe "ash_domain?/1" do
    test "returns true for Ash.Domain modules" do
      assert Introspection.ash_domain?(source_file(@ash_domain))
    end

    test "returns false for non-Ash modules" do
      refute Introspection.ash_domain?(source_file(@plain_module))
    end
  end

  describe "find_dsl_section/2" do
    test "finds the attributes section" do
      sf = source_file(@ash_resource)
      result = Introspection.find_dsl_section(sf, :attributes)
      assert {:attributes, _, _} = result
    end

    test "finds the actions section" do
      sf = source_file(@ash_resource)
      result = Introspection.find_dsl_section(sf, :actions)
      assert {:actions, _, _} = result
    end

    test "returns nil for missing section" do
      sf = source_file(@ash_resource)
      assert nil == Introspection.find_dsl_section(sf, :policies)
    end
  end

  describe "has_entity?/2" do
    test "detects entity in section" do
      sf = source_file(@ash_resource)
      attrs = Introspection.find_dsl_section(sf, :attributes)
      assert Introspection.has_entity?(attrs, :uuid_primary_key)
      assert Introspection.has_entity?(attrs, :timestamps)
    end

    test "returns false for missing entity" do
      sf = source_file(@ash_resource)
      attrs = Introspection.find_dsl_section(sf, :attributes)
      refute Introspection.has_entity?(attrs, :integer_primary_key)
    end

    test "returns false for nil section" do
      refute Introspection.has_entity?(nil, :anything)
    end
  end

  describe "find_entities/2" do
    test "finds all attribute entities" do
      sf = source_file(@ash_resource)
      attrs = Introspection.find_dsl_section(sf, :attributes)
      attributes = Introspection.find_entities(attrs, :attribute)
      assert length(attributes) == 2
    end

    test "returns empty list for nil section" do
      assert [] == Introspection.find_entities(nil, :attribute)
    end
  end

  describe "use_opts/2" do
    test "extracts opts from use call" do
      sf = source_file(@ash_resource)
      opts = Introspection.use_opts(sf, [:Ash, :Resource])
      assert is_list(opts)
      assert Keyword.has_key?(opts, :domain)
    end

    test "returns empty list when no opts" do
      source = """
      defmodule Foo do
        use Ash.Resource
      end
      """

      sf = source_file(source)
      assert [] == Introspection.use_opts(sf, [:Ash, :Resource])
    end
  end

  describe "section_line/1" do
    test "returns line number for a section" do
      sf = source_file(@ash_resource)
      attrs = Introspection.find_dsl_section(sf, :attributes)
      assert is_integer(Introspection.section_line(attrs))
    end

    test "returns nil for nil" do
      assert nil == Introspection.section_line(nil)
    end
  end

  describe "entity_opts/1" do
    test "extracts inline keyword opts" do
      sf = source_file(@ash_resource)
      attrs = Introspection.find_dsl_section(sf, :attributes)
      [title | _] = Introspection.find_entities(attrs, :attribute)
      opts = Introspection.entity_opts(title)
      assert Keyword.has_key?(opts, :public?)
    end

    test "returns empty list for entity without opts" do
      assert [] == Introspection.entity_opts({:timestamps, [line: 1], []})
    end

    test "excludes :do key from opts" do
      ast = {:create, [line: 1], [:create, [do: {:accept, [], [[:title]]}]]}
      refute Keyword.has_key?(Introspection.entity_opts(ast), :do)
    end
  end

  describe "entity_has_opt?/3" do
    test "detects inline opt value" do
      sf = source_file(@ash_resource)
      attrs = Introspection.find_dsl_section(sf, :attributes)
      [title | _] = Introspection.find_entities(attrs, :attribute)
      assert Introspection.entity_has_opt?(title, :public?, true)
      refute Introspection.entity_has_opt?(title, :public?, false)
    end

    test "detects opt in do block" do
      sf = source_file(@ash_resource)
      actions = Introspection.find_dsl_section(sf, :actions)
      [create] = Introspection.find_entities(actions, :create)
      assert Introspection.entity_has_opt?(create, :primary?, true)
    end
  end

  describe "entity_has_opt_key?/2" do
    test "detects inline opt key" do
      sf = source_file(@ash_resource)
      attrs = Introspection.find_dsl_section(sf, :attributes)
      [title | _] = Introspection.find_entities(attrs, :attribute)
      assert Introspection.entity_has_opt_key?(title, :public?)
      refute Introspection.entity_has_opt_key?(title, :sensitive?)
    end

    test "detects opt key in do block" do
      sf = source_file(@ash_resource)
      actions = Introspection.find_dsl_section(sf, :actions)
      [create] = Introspection.find_entities(actions, :create)
      assert Introspection.entity_has_opt_key?(create, :primary?)
    end
  end

  describe "entity_name/1" do
    test "extracts atom name from entity" do
      sf = source_file(@ash_resource)
      actions = Introspection.find_dsl_section(sf, :actions)
      [create] = Introspection.find_entities(actions, :create)
      assert :create == Introspection.entity_name(create)
    end

    test "returns nil for non-entity" do
      assert nil == Introspection.entity_name(:not_an_entity)
    end
  end

  describe "find_in_body/2" do
    test "finds call inside do block" do
      sf = source_file(@ash_resource)
      actions = Introspection.find_dsl_section(sf, :actions)
      [create] = Introspection.find_entities(actions, :create)
      assert {:accept, _, _} = Introspection.find_in_body(create, :accept)
    end

    test "returns nil when call not found" do
      sf = source_file(@ash_resource)
      actions = Introspection.find_dsl_section(sf, :actions)
      [create] = Introspection.find_entities(actions, :create)
      assert nil == Introspection.find_in_body(create, :description)
    end

    test "returns nil for non-tuple input" do
      assert nil == Introspection.find_in_body(nil, :anything)
    end
  end

  describe "section_body/1" do
    test "returns statements from section" do
      sf = source_file(@ash_resource)
      attrs = Introspection.find_dsl_section(sf, :attributes)
      body = Introspection.section_body(attrs)
      assert is_list(body)
      refute Enum.empty?(body)
    end

    test "returns empty list for nil" do
      assert [] == Introspection.section_body(nil)
    end
  end

  describe "section_has_entries?/1" do
    test "returns true for non-empty section" do
      sf = source_file(@ash_resource)
      attrs = Introspection.find_dsl_section(sf, :attributes)
      assert Introspection.section_has_entries?(attrs)
    end

    test "returns false for nil" do
      refute Introspection.section_has_entries?(nil)
    end
  end

  describe "actions_defined?/1" do
    test "returns true when explicit actions exist" do
      sf = source_file(@ash_resource)
      actions = Introspection.find_dsl_section(sf, :actions)
      assert Introspection.actions_defined?(actions)
    end

    test "returns true when defaults define actions" do
      source = """
      defmodule Foo do
        use Ash.Resource

        actions do
          defaults [:read, :destroy]
        end
      end
      """

      sf = source_file(source)
      actions = Introspection.find_dsl_section(sf, :actions)
      assert Introspection.actions_defined?(actions)
    end

    test "returns false for nil" do
      refute Introspection.actions_defined?(nil)
    end
  end

  describe "default_action_entries/1" do
    test "extracts entries from defaults call" do
      source = """
      defmodule Foo do
        use Ash.Resource

        actions do
          defaults [:read, create: :*]
        end
      end
      """

      sf = source_file(source)
      actions = Introspection.find_dsl_section(sf, :actions)
      [defaults] = Introspection.find_entities(actions, :defaults)
      entries = Introspection.default_action_entries(defaults)
      assert :read in entries
      assert {:create, :*} in entries
    end

    test "returns empty list for non-defaults" do
      assert [] == Introspection.default_action_entries(:not_defaults)
    end
  end

  describe "default_action_has_value?/3" do
    test "detects action type with specific value" do
      source = """
      defmodule Foo do
        use Ash.Resource

        actions do
          defaults [:read, create: :*]
        end
      end
      """

      sf = source_file(source)
      actions = Introspection.find_dsl_section(sf, :actions)
      [defaults] = Introspection.find_entities(actions, :defaults)
      assert Introspection.default_action_has_value?(defaults, :create, :*)
      refute Introspection.default_action_has_value?(defaults, :update, :*)
    end
  end

  describe "find_all_policy_entities/1" do
    test "finds top-level policy and bypass" do
      source = """
      defmodule Foo do
        use Ash.Resource

        policies do
          policy action_type(:read) do
            authorize_if always()
          end

          bypass action_type(:destroy) do
            authorize_if always()
          end
        end
      end
      """

      sf = source_file(source)
      policies = Introspection.find_dsl_section(sf, :policies)
      entities = Introspection.find_all_policy_entities(policies)
      assert length(entities) == 2
    end

    test "finds policies nested inside policy_group" do
      source = """
      defmodule Foo do
        use Ash.Resource

        policies do
          policy_group do
            policy action_type(:read) do
              authorize_if always()
            end
          end
        end
      end
      """

      sf = source_file(source)
      policies = Introspection.find_dsl_section(sf, :policies)
      entities = Introspection.find_all_policy_entities(policies)
      assert length(entities) == 1
    end

    test "returns empty list for nil" do
      assert [] == Introspection.find_all_policy_entities(nil)
    end
  end

  describe "entity_body/1" do
    test "extracts body statements from entity with do block" do
      sf = source_file(@ash_resource)
      actions = Introspection.find_dsl_section(sf, :actions)
      [create] = Introspection.find_entities(actions, :create)
      body = Introspection.entity_body(create)
      assert is_list(body)
      refute Enum.empty?(body)
    end

    test "returns empty list for entity without do block" do
      assert [] == Introspection.entity_body({:timestamps, [line: 1], []})
    end

    test "returns empty list for nil" do
      assert [] == Introspection.entity_body(nil)
    end
  end

  describe "find_use_line/2" do
    test "returns line number of use call" do
      sf = source_file(@ash_resource)
      line = Introspection.find_use_line(sf, [:Ash, :Resource])
      assert is_integer(line)
    end

    test "returns nil when use not found" do
      sf = source_file(@plain_module)
      assert nil == Introspection.find_use_line(sf, [:Ash, :Resource])
    end
  end

  describe "has_data_layer?/1" do
    test "returns true for non-embedded data layers" do
      source = """
      defmodule MyApp.Post do
        use Ash.Resource, domain: MyApp.Blog, data_layer: AshPostgres.DataLayer
      end
      """

      assert Introspection.has_data_layer?(source_file(source))
    end

    test "returns false for embedded resources" do
      source = """
      defmodule MyApp.Post do
        use Ash.Resource, data_layer: :embedded
      end
      """

      sf = source_file(source)

      refute Introspection.has_data_layer?(sf)
      assert Introspection.embedded_resource?(sf)
    end
  end
end
