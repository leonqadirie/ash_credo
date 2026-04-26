defmodule AshCredo.PluginIntegrationTest do
  @moduledoc """
  End-to-end smoke test for the AshCredo Credo plugin.

  Boots Credo programmatically against `test/integration/fixtures/plugin_smoke/`,
  pointing at that fixture's own `.credo.exs` (which uses `{AshCredo, []}`).
  Verifies the plugin's wiring as a whole: `register_default_config` is honored,
  the embedded check on/off toggles in `lib/ash_credo.ex` are applied, and the
  enabled checks actually run end-to-end.

  This complements the per-check unit tests under `test/ash_credo/check/`,
  which all bypass `Credo.Plugin` orchestration by calling
  `check_module.run/2` directly.
  """

  use ExUnit.Case, async: false

  alias AshCredo.Introspection.Compiled, as: CompiledIntrospection
  alias Credo.CLI.Output.Shell

  @fixture_dir Path.expand("fixtures/plugin_smoke", __DIR__)

  setup do
    CompiledIntrospection.clear_cache()
    :ok
  end

  test "plugin registers, default-on checks fire, default-off checks don't" do
    # Credo writes per-issue lines via a globally-registered GenServer
    # (`Credo.CLI.Output.Shell`) whose group leader was set at app boot, so
    # `ExUnit.CaptureIO` cannot intercept them. The shell exposes
    # `suppress_output/1` for exactly this case - flip the flag for the
    # duration of the run so the test output stays clean. The function returns
    # the result of the trailing GenServer call rather than the callback's
    # value, so route the `Execution` struct out via send/receive.
    parent = self()

    Shell.suppress_output(fn ->
      exec =
        Credo.run([
          "--config-file",
          Path.join(@fixture_dir, ".credo.exs"),
          "--working-dir",
          @fixture_dir,
          "--mute-exit-status",
          "--format",
          "oneline"
        ])

      send(parent, {:credo_exec, exec})
    end)

    exec =
      receive do
        {:credo_exec, exec} -> exec
      after
        0 -> flunk("Credo.run callback did not send the Execution struct")
      end

    issues = Credo.Execution.get_issues(exec)
    triggered = MapSet.new(issues, & &1.check)

    # Default-on: the plugin's embedded config has `{MissingMacroDirective, []}`.
    # The fixture has an `Ash.Query.filter(...)` call without `require Ash.Query`,
    # so the check must fire.
    assert AshCredo.Check.Warning.MissingMacroDirective in triggered,
           """
           Expected `MissingMacroDirective` to fire (default-on in plugin config).
           Triggered checks: #{inspect(MapSet.to_list(triggered))}
           Issues: #{inspect(Enum.map(issues, &{&1.check, &1.message}))}
           """

    # Default-off: the plugin's embedded config has `{UseCodeInterface, false}`.
    # The fixture has an `Ash.read!(AshCredoFixtures.Blog.Post, action: :read)`
    # call that WOULD trigger the check if it were on. It must NOT fire here.
    refute AshCredo.Check.Refactor.UseCodeInterface in triggered,
           """
           `UseCodeInterface` is `false` in the plugin's embedded config and
           must not fire by default.
           Triggered checks: #{inspect(MapSet.to_list(triggered))}
           """
  end
end
