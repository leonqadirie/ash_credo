defmodule AshCredo.PluginIntegrationTest do
  @moduledoc """
  End-to-end smoke test for the AshCredo Credo plugin.

  Boots Credo programmatically against `test/integration/fixtures/plugin_smoke/`,
  pointing at that fixture's own `.credo.exs` (which uses `{AshCredo, []}`).
  Verifies the plugin's wiring as a whole: `register_default_config` is honored,
  the embedded check on/off toggles in `lib/ash_credo.ex` are applied, the
  enabled checks actually run end-to-end, and a user-enabled compiled check
  delivers issues built from `Ash.Resource.Info` introspection through the
  whole pipeline (regression guard for issue #187).

  This complements the per-check unit tests under `test/ash_credo/check/`,
  which all bypass `Credo.Plugin` orchestration by calling
  `check_module.run/2` directly.
  """

  use ExUnit.Case, async: false

  alias AshCredo.Cache
  alias AshCredo.Introspection.Compiled, as: CompiledIntrospection
  alias Credo.CLI.Output.Shell

  @fixture_dir Path.expand("fixtures/plugin_smoke", __DIR__)

  setup do
    CompiledIntrospection.clear_cache()
    :ok
  end

  test "plugin registers, default-on checks fire, default-off checks don't, compiled checks deliver" do
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

    # User-enabled compiled check: the fixture's `.credo.exs` enables
    # `MissingCodeInterface` (default-off in the plugin's embedded config) via
    # `checks: %{extra: [...]}`, the way a user would. The fixture's
    # `lib/post.ex` has a deliberately minimal body - the interface-less
    # actions the check reports on (e.g. `:draft`) exist only on the compiled
    # `AshCredoFixtures.Blog.Post` from `test/support/fixtures/`. Issues
    # naming them prove that compiled-introspection results survive the whole
    # Credo pipeline (regression guard for issue #187, which alleged they are
    # silently dropped).
    code_interface_issues =
      Enum.filter(issues, &(&1.check == AshCredo.Check.Design.MissingCodeInterface))

    assert code_interface_issues != [],
           """
           Expected the user-enabled compiled check `MissingCodeInterface` to
           deliver issues end-to-end through the plugin pipeline.
           Triggered checks: #{inspect(MapSet.to_list(triggered))}
           Issues: #{inspect(Enum.map(issues, &{&1.check, &1.message}))}
           """

    assert Enum.any?(code_interface_issues, &(&1.message =~ ":draft")),
           """
           Expected an issue for action `:draft`, which is visible only via
           `Ash.Resource.Info` on the compiled fixture module - not in the
           analyzed source file.
           Messages: #{inspect(Enum.map(code_interface_issues, & &1.message))}
           """

    # `AshCredo.ClearCacheTask` is appended to the `:halt_execution` pipeline
    # group, so the introspection cache must be empty after the run completes.
    # This proves the post-run task fired end-to-end.
    refute Cache.member?({AshCredo.Introspection.Compiled, :ash_available?}),
           "Cache should be empty after the Credo run; ClearCacheTask did not fire"
  end
end
