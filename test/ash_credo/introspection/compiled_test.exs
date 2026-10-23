defmodule AshCredo.Introspection.CompiledTest do
  @moduledoc """
  Tests the thin public accessors of the compiled-introspection gateway.
  Checks consume the lower-level `inspect_module/1`, so the per-aspect
  accessors (`actions/1`, `primary_key/1`, `authorizers/1`, ...) and their
  error propagation are only exercised here. Each resolves against the
  loadable `AshCredoFixtures.*` resources.
  """
  use AshCredo.CheckCase, clear_cache: true

  alias AshCredo.Introspection.Compiled

  @post AshCredoFixtures.Blog.Post
  @plain AshCredoFixtures.Plain

  describe "macros/1" do
    test "preserves exact macro arities, including default arguments" do
      assert {:ok, macros} = Compiled.macros(AshCredoFixtures.FakeMacros)

      assert macros ==
               MapSet.new([
                 {:do_thing, 1},
                 {:other, 2},
                 {:with_default, 1},
                 {:with_default, 2},
                 {:no_args, 0}
               ])

      refute MapSet.member?(macros, {:do_thing, 2})
      refute MapSet.member?(macros, {:regular, 1})
    end
  end

  describe "functions/1" do
    test "returns exported functions, excluding macros" do
      assert {:ok, functions} = Compiled.functions(AshCredoFixtures.FakeMacros)

      assert MapSet.member?(functions, {:do_thing, 2})
      refute MapSet.member?(functions, {:do_thing, 1})
    end

    test "returns :not_loadable for a module that does not exist" do
      assert Compiled.functions(AshCredoFixtures.DoesNotExist) == {:error, :not_loadable}
    end
  end

  describe "specs/1" do
    test "returns the typespecs compiled into the module" do
      assert Enum.any?(Compiled.specs(Compiled), &match?({{:specs, 1}, _}, &1))
    end

    test "returns [] for a module that does not exist" do
      assert Compiled.specs(AshCredoFixtures.DoesNotExist) == []
    end
  end

  describe "resource aspect accessors" do
    test "domain/1 returns the declared domain" do
      assert Compiled.domain(@post) == {:ok, AshCredoFixtures.Blog}
    end

    test "interfaces/1 returns the code-interface entries" do
      assert {:ok, interfaces} = Compiled.interfaces(@post)
      assert Enum.any?(interfaces, &(&1.name == :archive))
    end

    test "calculation_interfaces/1 returns the calculation-interface entries" do
      assert {:ok, [_ | _]} =
               Compiled.calculation_interfaces(AshCredoFixtures.Blog.WithCalcInterface)
    end

    test "actions/1 returns the resolved action structs" do
      assert {:ok, actions} = Compiled.actions(@post)
      assert Enum.any?(actions, &(&1.name == :read and &1.type == :read))
    end

    test "attributes/1 returns the resolved attribute structs" do
      assert {:ok, attributes} = Compiled.attributes(@post)
      assert Enum.any?(attributes, &(&1.name == :id))
    end

    test "primary_key/1 returns the primary key attribute names" do
      assert Compiled.primary_key(@post) == {:ok, [:id]}
    end

    test "identities/1 returns the declared identities" do
      assert {:ok, identities} = Compiled.identities(AshCredoFixtures.Accounts.Profile)
      assert Enum.any?(identities, &(&1.name == :unique_email))
    end

    test "authorizers/1 returns the declared authorizer modules" do
      assert {:ok, authorizers} = Compiled.authorizers(AshCredoFixtures.Blog.WithAuthorizer)
      assert Ash.Policy.Authorizer in authorizers
    end

    test "policies/1 returns policy entries, or [] without an authorizer" do
      assert {:ok, [_ | _]} =
               Compiled.policies(AshCredoFixtures.Blog.WithAuthorizerAndPolicies)

      assert Compiled.policies(@post) == {:ok, []}
    end
  end

  describe "action/2" do
    test "returns the action struct for a known action" do
      assert {:ok, action} = Compiled.action(@post, :read)
      assert action.name == :read
    end

    test "returns :unknown_action for an undefined action" do
      assert Compiled.action(@post, :nope) == {:error, :unknown_action}
    end
  end

  describe "domain_resources/1" do
    test "returns the resources registered in a domain" do
      assert {:ok, resources} = Compiled.domain_resources(AshCredoFixtures.Blog)
      assert @post in resources
    end

    test "returns :not_a_domain for a resource module" do
      assert Compiled.domain_resources(@post) == {:error, :not_a_domain}
    end
  end

  describe "domain-level interface lookups" do
    @figure AshCredoFixtures.Blog.Figure

    test "domain_interfaces/2 returns both action and calculation interfaces" do
      definitions = Compiled.domain_interfaces(AshCredoFixtures.Blog, @figure)

      assert Enum.any?(definitions, &match?(%Ash.Resource.Interface{name: :list_figures}, &1))

      assert Enum.any?(
               definitions,
               &match?(%Ash.Resource.CalculationInterface{name: :figure_total_value}, &1)
             )
    end

    test "domain_interface/3 skips calculation interfaces" do
      assert %Ash.Resource.Interface{name: :list_figures} =
               Compiled.domain_interface(AshCredoFixtures.Blog, @figure, :read)

      assert Compiled.domain_interface(AshCredoFixtures.Blog, @figure, :draft) == nil
    end

    test "find_interface/2 rejects the nil action name of a calculation interface" do
      definitions = Compiled.domain_interfaces(AshCredoFixtures.Blog, @figure)
      calc_iface = Enum.find(definitions, &match?(%Ash.Resource.CalculationInterface{}, &1))
      action_name = Compiled.interface_action_name(calc_iface)

      assert_raise FunctionClauseError, fn ->
        Compiled.find_interface(definitions, action_name)
      end
    end

    test "interface_action_name/1 prefers the explicit action over the name" do
      {:ok, interfaces} = Compiled.interfaces(@post)

      assert interfaces
             |> Enum.find(&(&1.name == :published_posts))
             |> Compiled.interface_action_name() == :published

      assert interfaces |> Enum.find(&(&1.name == :archive)) |> Compiled.interface_action_name() ==
               :archive
    end

    test "interface_action_name/1 returns nil for a calculation interface" do
      calc_iface =
        AshCredoFixtures.Blog
        |> Compiled.domain_interfaces(@figure)
        |> Enum.find(&match?(%Ash.Resource.CalculationInterface{}, &1))

      assert Compiled.interface_action_name(calc_iface) == nil
    end

    test "code_interface_bang/2 resolves a domain define_calculation" do
      assert {:ok,
              %{
                scope: :domain,
                interface: %Ash.Resource.CalculationInterface{name: :figure_total_value},
                resource: @figure
              }} = Compiled.code_interface_bang(AshCredoFixtures.Blog, :figure_total_value!)
    end

    test "code_interface_bang/2 resolves a define_calculation named like an action" do
      for module <- [AshCredoFixtures.Blog, @figure] do
        assert {:ok, %{interface: %Ash.Resource.CalculationInterface{name: :draft} = iface}} =
                 Compiled.code_interface_bang(module, :draft!)

        assert Compiled.interface_action_name(iface) == nil
      end
    end
  end

  describe "error propagation through the accessors" do
    test "a non-resource module yields :not_a_resource" do
      assert Compiled.interfaces(@plain) == {:error, :not_a_resource}
      assert Compiled.primary_key(@plain) == {:error, :not_a_resource}
      assert Compiled.authorizers(@plain) == {:error, :not_a_resource}
      assert Compiled.action(@plain, :read) == {:error, :not_a_resource}
    end

    test "a module raising mid-introspection yields :not_loadable instead of crashing" do
      half_purged = AshCredoFixtures.HalfPurgedResource

      assert Compiled.inspect_module(half_purged) == {:error, :not_loadable}
      assert Compiled.attributes(half_purged) == {:error, :not_loadable}
    end
  end
end
