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

  describe "resource_modules/1" do
    test "returns resource modules in file order" do
      source = """
      defmodule MyApp.Post do
        use Ash.Resource, domain: MyApp.Blog, data_layer: AshPostgres.DataLayer

        attributes do
          uuid_primary_key :id
        end

        defmodule Draft do
          use Ash.Resource, domain: MyApp.Blog

          actions do
            read :read
          end
        end
      end
      """

      [outer, inner] = Introspection.resource_modules(source_file(source))

      assert Introspection.has_data_layer?(outer)
      refute Introspection.has_data_layer?(inner)
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

    test "only inspects the given module body" do
      source = """
      defmodule MyApp.Post do
        use Ash.Resource, domain: MyApp.Blog

        defmodule Draft do
          use Ash.Resource, domain: MyApp.Blog

          actions do
            read :read
          end
        end
      end
      """

      [outer, inner] = Introspection.resource_modules(source_file(source))

      assert nil == Introspection.find_dsl_section(outer, :actions)
      assert {:actions, _, _} = Introspection.find_dsl_section(inner, :actions)
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

  describe "entities/2" do
    test "finds all attribute entities" do
      sf = source_file(@ash_resource)
      attrs = Introspection.find_dsl_section(sf, :attributes)
      attributes = Introspection.entities(attrs, :attribute)
      assert length(attributes) == 2
    end

    test "returns empty list for nil section" do
      assert [] == Introspection.entities(nil, :attribute)
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

    test "extracts opts from the specific module only" do
      source = """
      defmodule MyApp.Post do
        use Ash.Resource, domain: MyApp.Blog, data_layer: AshPostgres.DataLayer

        defmodule Draft do
          use Ash.Resource, domain: MyApp.Blog
        end
      end
      """

      [outer, inner] = Introspection.resource_modules(source_file(source))

      assert Introspection.has_data_layer?(outer)
      refute Introspection.has_data_layer?(inner)
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

  describe "module_aliases/2" do
    test "returns top-level aliases declared before the given line" do
      source = """
      defmodule MyApp.Post do
        alias Ash.Policy.Authorizer
        alias Ash.Policy.{Bypass, Check}

        use Ash.Resource, authorizers: [Authorizer, Bypass]
      end
      """

      [resource] = Introspection.resource_modules(source_file(source))
      aliases = Introspection.module_aliases(resource, before_line: 5)

      assert {[:Authorizer], [:Ash, :Policy, :Authorizer]} in aliases
      assert {[:Bypass], [:Ash, :Policy, :Bypass]} in aliases
      assert {[:Check], [:Ash, :Policy, :Check]} in aliases
    end

    test "ignores aliases declared inside nested modules" do
      source = """
      defmodule MyApp.Post do
        alias Ash.Policy.Authorizer

        defmodule Draft do
          alias Ash.Policy.Check, as: DraftCheck
        end

        use Ash.Resource, authorizers: [Authorizer]
      end
      """

      [resource] = Introspection.resource_modules(source_file(source))
      aliases = Introspection.module_aliases(resource, before_line: 8)

      assert {[:Authorizer], [:Ash, :Policy, :Authorizer]} in aliases

      refute Enum.any?(aliases, fn {alias_segments, _target_segments} ->
               alias_segments == [:DraftCheck]
             end)
    end
  end

  describe "expand_alias/2" do
    test "expands explicit and prefix aliases" do
      aliases = [
        {[:PolicyAuthorizer], [:Ash, :Policy, :Authorizer]},
        {[:Policy], [:Ash, :Policy]}
      ]

      assert [:Ash, :Policy, :Authorizer] ==
               Introspection.expand_alias([:PolicyAuthorizer], aliases)

      assert [:Ash, :Policy, :Authorizer] ==
               Introspection.expand_alias([:Policy, :Authorizer], aliases)
    end
  end

  describe "resource_context/1" do
    test "returns shared resource metadata" do
      source = """
      defmodule MyApp.Post do
        alias Ash.Policy.Authorizer

        use Ash.Resource,
          domain: MyApp.Blog,
          authorizers: [Authorizer]

        actions do
          read :read
        end
      end
      """

      [resource] = Introspection.resource_modules(source_file(source))
      context = Introspection.resource_context(resource)

      assert context.module_ast == resource
      assert is_integer(context.use_line)
      assert Keyword.has_key?(context.use_opts, :domain)
      assert {[:Authorizer], [:Ash, :Policy, :Authorizer]} in context.aliases
      assert {:actions, _, _} = Introspection.find_dsl_section(context, :actions)
    end
  end

  describe "resolved_module_ref/3" do
    test "resolves aliased module references from resource context" do
      source = """
      defmodule MyApp.Post do
        alias Ash.Policy.Authorizer

        use Ash.Resource,
          domain: MyApp.Blog,
          authorizers: [Authorizer]
      end
      """

      [resource] = Introspection.resource_modules(source_file(source))
      context = Introspection.resource_context(resource)
      [authorizer] = Keyword.get(context.use_opts, :authorizers)

      assert [:Ash, :Policy, :Authorizer] ==
               Introspection.resolved_module_ref(authorizer, context)

      assert Introspection.module_ref?(authorizer, context, [:Ash, :Policy, :Authorizer])
    end

    test "does not use aliases declared after the reference" do
      source = """
      defmodule MyApp.Post do
        use Ash.Resource,
          domain: MyApp.Blog,
          authorizers: [Authorizer]

        alias Ash.Policy.Authorizer
      end
      """

      [resource] = Introspection.resource_modules(source_file(source))
      context = Introspection.resource_context(resource)
      [authorizer] = Keyword.get(context.use_opts, :authorizers)

      assert [:Authorizer] == Introspection.resolved_module_ref(authorizer, context)
      refute Introspection.module_ref?(authorizer, context, [:Ash, :Policy, :Authorizer])
    end
  end

  describe "action_entities/2" do
    test "returns explicit actions for the requested types" do
      source = """
      defmodule Foo do
        use Ash.Resource

        actions do
          read :read
          create :create
          action :custom
        end
      end
      """

      sf = source_file(source)
      actions = Introspection.find_dsl_section(sf, :actions)

      assert length(Introspection.action_entities(actions, [:read, :create])) == 2
      assert length(Introspection.action_entities(actions)) == 3
    end
  end

  describe "option_occurrences/2" do
    test "returns normalized inline and body option values" do
      ast =
        {:create, [line: 1],
         [:create, [accept: [:title]], [do: {:__block__, [], [{:primary?, [line: 2], [true]}]}]]}

      assert [{[:title], 1}] == Introspection.option_occurrences(ast, :accept)
      assert [{true, 2}] == Introspection.option_occurrences(ast, :primary?)
    end

    test "returns section option values from the do block" do
      source = """
      defmodule Foo do
        use Ash.Resource

        actions do
          default_accept [:name]
        end
      end
      """

      sf = source_file(source)
      actions = Introspection.find_dsl_section(sf, :actions)

      assert [{[:name], line_no}] = Introspection.option_occurrences(actions, :default_accept)
      assert is_integer(line_no)
    end
  end

  describe "entity_opts/1" do
    test "extracts inline keyword opts" do
      sf = source_file(@ash_resource)
      attrs = Introspection.find_dsl_section(sf, :attributes)
      [title | _] = Introspection.entities(attrs, :attribute)
      opts = Introspection.entity_opts(title)
      assert Keyword.has_key?(opts, :public?)
    end

    test "extracts inline opts when entity also has a do block" do
      ast =
        {:create, [line: 1], [:create, [primary?: true], [do: {:accept, [], [[:title]]}]]}

      assert [primary?: true] == Introspection.entity_opts(ast)
    end

    test "extracts inline opts from merged do syntax" do
      ast =
        {:create, [line: 1], [:create, [primary?: true, do: {:accept, [], [[:title]]}]]}

      assert [primary?: true] == Introspection.entity_opts(ast)
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
      [title | _] = Introspection.entities(attrs, :attribute)
      assert Introspection.entity_has_opt?(title, :public?, true)
      refute Introspection.entity_has_opt?(title, :public?, false)
    end

    test "detects inline opt value when entity also has a do block" do
      ast =
        {:create, [line: 1], [:create, [primary?: true], [do: {:accept, [], [[:title]]}]]}

      assert Introspection.entity_has_opt?(ast, :primary?, true)
    end

    test "detects opt in do block" do
      sf = source_file(@ash_resource)
      actions = Introspection.find_dsl_section(sf, :actions)
      [create] = Introspection.entities(actions, :create)
      assert Introspection.entity_has_opt?(create, :primary?, true)
    end
  end

  describe "entity_has_opt_key?/2" do
    test "detects inline opt key" do
      sf = source_file(@ash_resource)
      attrs = Introspection.find_dsl_section(sf, :attributes)
      [title | _] = Introspection.entities(attrs, :attribute)
      assert Introspection.entity_has_opt_key?(title, :public?)
      refute Introspection.entity_has_opt_key?(title, :sensitive?)
    end

    test "detects opt key in do block" do
      sf = source_file(@ash_resource)
      actions = Introspection.find_dsl_section(sf, :actions)
      [create] = Introspection.entities(actions, :create)
      assert Introspection.entity_has_opt_key?(create, :primary?)
    end
  end

  describe "entity_name/1" do
    test "extracts atom name from entity" do
      sf = source_file(@ash_resource)
      actions = Introspection.find_dsl_section(sf, :actions)
      [create] = Introspection.entities(actions, :create)
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
      [create] = Introspection.entities(actions, :create)
      assert {:accept, _, _} = Introspection.find_in_body(create, :accept)
    end

    test "returns nil when call not found" do
      sf = source_file(@ash_resource)
      actions = Introspection.find_dsl_section(sf, :actions)
      [create] = Introspection.entities(actions, :create)
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
      [defaults] = Introspection.entities(actions, :defaults)
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
      [defaults] = Introspection.entities(actions, :defaults)
      assert Introspection.default_action_has_value?(defaults, :create, :*)
      refute Introspection.default_action_has_value?(defaults, :update, :*)
    end
  end

  describe "policy_entities/1" do
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
      entities = Introspection.policy_entities(policies)
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
      entities = Introspection.policy_entities(policies)
      assert length(entities) == 1
    end

    test "returns empty list for nil" do
      assert [] == Introspection.policy_entities(nil)
    end
  end

  describe "entity_body/1" do
    test "extracts body statements from entity with do block" do
      sf = source_file(@ash_resource)
      actions = Introspection.find_dsl_section(sf, :actions)
      [create] = Introspection.entities(actions, :create)
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

    test "works with resource context" do
      source = """
      defmodule MyApp.Post do
        use Ash.Resource, domain: MyApp.Blog, data_layer: AshPostgres.DataLayer
      end
      """

      [resource] = Introspection.resource_modules(source_file(source))
      context = Introspection.resource_context(resource)

      assert {:__aliases__, _, [:AshPostgres, :DataLayer]} =
               Introspection.resource_data_layer(context)

      assert Introspection.has_data_layer?(context)
      refute Introspection.embedded_resource?(context)
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

    test "detects embedded resources from resource context" do
      source = """
      defmodule MyApp.Post do
        use Ash.Resource, data_layer: :embedded
      end
      """

      [resource] = Introspection.resource_modules(source_file(source))
      context = Introspection.resource_context(resource)

      refute Introspection.has_data_layer?(context)
      assert Introspection.embedded_resource?(context)
    end
  end
end
