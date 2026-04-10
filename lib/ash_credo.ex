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
            {AshCredo.Check.Warning.AuthorizeFalse, false},
            {AshCredo.Check.Warning.AuthorizerWithoutPolicies, false},
            {AshCredo.Check.Warning.EmptyDomain, false},
            {AshCredo.Check.Warning.MissingChangeWrapper, []},
            {AshCredo.Check.Warning.MissingDomain, false},
            {AshCredo.Check.Warning.MissingMacroDirective, false},
            {AshCredo.Check.Warning.MissingPrimaryKey, false},
            {AshCredo.Check.Warning.NoActions, false},
            {AshCredo.Check.Warning.OverlyPermissivePolicy, false},
            {AshCredo.Check.Warning.PinnedTimeInExpression, false},
            {AshCredo.Check.Warning.SensitiveAttributeExposed, false},
            {AshCredo.Check.Warning.SensitiveFieldInAccept, false},
            {AshCredo.Check.Warning.UnknownAction, false},
            {AshCredo.Check.Warning.WildcardAcceptOnAction, false},
            # Design
            {AshCredo.Check.Design.MissingCodeInterface, false},
            {AshCredo.Check.Design.MissingIdentity, false},
            {AshCredo.Check.Design.MissingPrimaryAction, false},
            {AshCredo.Check.Design.MissingTimestamps, false},
            # Readability
            {AshCredo.Check.Readability.ActionMissingDescription, false},
            {AshCredo.Check.Readability.BelongsToMissingAllowNil, false},
            # Refactor
            {AshCredo.Check.Refactor.LargeResource, false},
            {AshCredo.Check.Refactor.UseCodeInterface, false}
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
