defmodule AshCredo do
  @moduledoc """
  Credo checks for Ash Framework.

  Provides pre-built checks that detect common Ash anti-patterns
  by pattern matching on unexpanded source AST.

  ## Plugin Usage

  Add to your `.credo.exs`:

      %{configs: [%{
        name: "default",
        plugins: [{AshCredo, []}]
      }]}
  """

  import Credo.Plugin

  @config_file """
  %{
    configs: [
      %{
        name: "default",
        checks: %{
          extra: [
            {AshCredo.Check.Ash.MissingPrimaryKey, []},
            {AshCredo.Check.Ash.MissingTimestamps, []},
            {AshCredo.Check.Ash.SensitiveAttributeExposed, []},
            {AshCredo.Check.Ash.AuthorizerWithoutPolicies, []},
            {AshCredo.Check.Ash.MissingPrimaryAction, []},
            {AshCredo.Check.Ash.OverlyPermissivePolicy, []},
            {AshCredo.Check.Ash.WildcardAcceptOnAction, []},
            {AshCredo.Check.Ash.SensitiveFieldInAccept, []},
            {AshCredo.Check.Ash.MissingDomain, []},
            {AshCredo.Check.Ash.NoActions, []},
            {AshCredo.Check.Ash.EmptyDomain, []},
            {AshCredo.Check.Ash.MissingIdentity, []},
            {AshCredo.Check.Ash.BelongsToMissingAllowNil, []},
            {AshCredo.Check.Ash.MissingCodeInterface, []},
            {AshCredo.Check.Ash.LargeResource, []},
            {AshCredo.Check.Ash.ActionMissingDescription, []}
          ]
        }
      }
    ]
  }
  """

  def init(exec) do
    register_default_config(exec, @config_file)
  end
end
