defmodule AshCredo.CompiledCheckTest do
  use AshCredo.CheckCase

  alias AshCredo.Cache
  alias AshCredo.Introspection.Compiled, as: CompiledIntrospection

  # Mirrors the private key in AshCredo.Introspection.Compiled that
  # `ash_available?/0` reads. There is no public setter, so priming it is the
  # only way to exercise the Ash-missing branch: Ash is always loaded in the
  # test VM, so `ash_available?/0` would otherwise always be true.
  @ash_available_key {CompiledIntrospection, :ash_available?}

  # Default `active?/2` (provided by the macro). Records that the body ran so a
  # test can assert it did - or, via refute, that the guard short-circuited.
  defmodule DefaultProbe do
    use AshCredo.CompiledCheck, category: :warning

    @impl AshCredo.CompiledCheck
    def run_compiled(_source_file, _params) do
      send(self(), :run_compiled_ran)
      []
    end
  end

  # Overrides `active?/2` to false: the check is disabled regardless of Ash.
  defmodule InactiveProbe do
    use AshCredo.CompiledCheck, category: :warning

    @impl AshCredo.CompiledCheck
    def active?(_source_file, _params), do: false

    @impl AshCredo.CompiledCheck
    def run_compiled(_source_file, _params) do
      send(self(), :run_compiled_ran)
      []
    end
  end

  @source "defmodule Sample do\nend\n"

  setup do
    Cache.ensure_started!()
    CompiledIntrospection.clear_cache()
    on_exit(fn -> CompiledIntrospection.clear_cache() end)
    :ok
  end

  describe "active?/2 gating" do
    test "the default active?/2 is true, so the body runs when Ash is available" do
      assert [] == run_check(DefaultProbe, @source)
      assert_received :run_compiled_ran
    end

    test "active?/2 false short-circuits: no issues and the body never runs" do
      assert [] == run_check(InactiveProbe, @source)
      refute_received :run_compiled_ran
    end
  end

  describe "Ash-availability guard" do
    test "Ash unavailable: emits one ash-missing diagnostic and skips the body" do
      Cache.put(@ash_available_key, false)

      assert [issue] = run_check(DefaultProbe, @source)
      assert issue.message =~ "Ash is not loaded"
      refute_received :run_compiled_ran
    end

    test "active?/2 false suppresses the ash-missing diagnostic too" do
      Cache.put(@ash_available_key, false)

      assert [] == run_check(InactiveProbe, @source)
      refute_received :run_compiled_ran
    end
  end
end
