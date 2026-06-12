defmodule AshCredo do
  @moduledoc """
  Credo checks for Ash Framework.

  Provides pre-built checks that detect common Ash anti-patterns.
  Some checks analyse unexpanded source AST; others introspect the
  compiled modules to see the fully-resolved DSL state, including
  anything Spark transformers and extensions contribute.

  Checks that introspect compiled modules require the project to be
  compiled before running `mix credo` (for example via a Mix alias
  like `lint: ["compile", "credo --strict"]`); otherwise they emit a
  configuration diagnostic and become a no-op.

  ## Plugin Usage

  Add to your `.credo.exs`:

      %{configs: [%{
        name: "default",
        plugins: [{AshCredo, []}]
      }]}
  """

  import Credo.Plugin

  alias AshCredo.Cache

  @config_file """
  %{
    configs: [
      %{
        name: "default",
        checks: %{
          extra: [
            # Warning
            {AshCredo.Check.Warning.ActorOnCallOptions, false},
            {AshCredo.Check.Warning.AuthorizeFalse, false},
            {AshCredo.Check.Warning.AuthorizerWithoutPolicies, false},
            {AshCredo.Check.Warning.CompileTimeDefault, []},
            {AshCredo.Check.Warning.EmptyDomain, false},
            {AshCredo.Check.Warning.MissingChangeWrapper, []},
            {AshCredo.Check.Warning.MissingDomain, false},
            {AshCredo.Check.Warning.MissingMacroDirective, []},
            {AshCredo.Check.Warning.MissingPrepareWrapper, []},
            {AshCredo.Check.Warning.MissingValidationWrapper, []},
            {AshCredo.Check.Warning.OverlyPermissivePolicy, false},
            {AshCredo.Check.Warning.PinnedTimeInExpression, []},
            {AshCredo.Check.Warning.RedundantValidation, false},
            {AshCredo.Check.Warning.SensitiveAttributeExposed, false},
            {AshCredo.Check.Warning.SensitiveFieldInAccept, false},
            {AshCredo.Check.Warning.UnknownAction, false},
            {AshCredo.Check.Warning.WildcardAcceptOnAction, false},
            # Refactor
            {AshCredo.Check.Refactor.AnonymousFunctionInDsl, false},
            {AshCredo.Check.Refactor.DirectiveInFunctionBody, false},
            {AshCredo.Check.Refactor.LargeResource, false},
            {AshCredo.Check.Refactor.RaisingCall, false},
            {AshCredo.Check.Refactor.UseCodeInterface, false},
            # Design
            {AshCredo.Check.Design.MissingCodeInterface, false},
            {AshCredo.Check.Design.MissingIdentity, false},
            {AshCredo.Check.Design.MissingPrimaryAction, false},
            {AshCredo.Check.Design.MissingTimestamps, false},
            # Readability
            {AshCredo.Check.Readability.ActionMissingDescription, false},
            {AshCredo.Check.Readability.BelongsToMissingAllowNil, false}
          ]
        }
      }
    ]
  }
  """

  # The missing-table hint in AshCredo.Cache quotes this registration
  # (`{AshCredo, []}` under `plugins`); keep them in sync if it changes.
  def init(exec) do
    Cache.ensure_started!()
    Cache.clear()

    exec
    |> register_default_config(@config_file)
    |> append_task(:halt_execution, AshCredo.ClearCacheTask)
  end
end
