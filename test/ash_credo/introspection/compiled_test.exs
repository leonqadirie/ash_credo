defmodule AshCredo.Introspection.CompiledTest do
  @moduledoc """
  Tests the thin public accessors of the compiled-introspection gateway.
  Checks consume the lower-level `inspect_module/1`, so the per-aspect
  accessors (`actions/1`, `primary_key/1`, `authorizers/1`, ...) and their
  error propagation are only exercised here. Each resolves against the
  loadable `AshCredoFixtures.*` resources.
  """
  use ExUnit.Case, async: false

  alias AshCredo.Introspection.Compiled

  @post AshCredoFixtures.Blog.Post
  @plain AshCredoFixtures.Plain

  setup do
    Compiled.clear_cache()
    :ok
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

  describe "error propagation through the accessors" do
    test "a non-resource module yields :not_a_resource" do
      assert Compiled.interfaces(@plain) == {:error, :not_a_resource}
      assert Compiled.primary_key(@plain) == {:error, :not_a_resource}
      assert Compiled.authorizers(@plain) == {:error, :not_a_resource}
      assert Compiled.action(@plain, :read) == {:error, :not_a_resource}
    end
  end
end
