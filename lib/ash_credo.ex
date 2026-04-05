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
            # Warning
            {AshCredo.Check.Warning.AuthorizerWithoutPolicies, []},
            {AshCredo.Check.Warning.EmptyDomain, []},
            {AshCredo.Check.Warning.MissingChangeWrapper, []},
            {AshCredo.Check.Warning.MissingDomain, []},
            {AshCredo.Check.Warning.MissingPrimaryKey, []},
            {AshCredo.Check.Warning.NoActions, []},
            {AshCredo.Check.Warning.OverlyPermissivePolicy, []},
            {AshCredo.Check.Warning.PinnedTimeInExpression, []},
            {AshCredo.Check.Warning.SensitiveAttributeExposed, []},
            {AshCredo.Check.Warning.SensitiveFieldInAccept, []},
            {AshCredo.Check.Warning.WildcardAcceptOnAction, []},
            # Design
            {AshCredo.Check.Design.MissingCodeInterface, []},
            {AshCredo.Check.Design.MissingIdentity, []},
            {AshCredo.Check.Design.MissingPrimaryAction, []},
            {AshCredo.Check.Design.MissingTimestamps, []},
            # Readability
            {AshCredo.Check.Readability.ActionMissingDescription, []},
            {AshCredo.Check.Readability.BelongsToMissingAllowNil, []},
            # Refactor
            {AshCredo.Check.Refactor.LargeResource, []}
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
