defmodule AshCredo.CheckSmokeTest do
  @moduledoc """
  Runs every check over every fixture and asserts that none of them raise.

  Per-check tests only cover the DSL variants their author thought of, so a
  check can crash on a variant that no test for that check uses. This test
  runs every check over:

    * the source of every fixture file, so DSL-walking checks see real DSL
      and compiled checks resolve the real modules;
    * generated caller modules, one per fixture resource and caller
      context (outside any domain, and inside the resource's own domain).
      Each caller reaches every action through each call pattern that
      `AshCallResolver` recognises for the action's type, including a
      record bound to a variable, plus every resource- and domain-level
      code-interface bang.

  Each check runs once with its defaults and once per param variant: every
  boolean param flipped, plus every non-default value of the enum params
  in `@enum_params`.

  `AshCredoFixtures.KitchenSink` exists for this test: it combines DSL
  variants that the per-check fixtures leave out.
  """
  use AshCredo.CheckCase, clear_cache: true

  alias Ash.Domain.Info, as: DomainInfo
  alias AshCredo.CheckRegistry
  alias AshCredo.Introspection.Compiled

  @fixture_glob "test/support/fixtures/*.ex"

  # Non-boolean params with a closed set of values, keyed by param name.
  @enum_params %{prefer_interface_scope: [:auto, :resource, :domain]}

  test "no check raises on any fixture source or fixture caller" do
    checks = CheckRegistry.check_modules()
    fixtures = fixture_sources()
    callers = caller_sources()

    # Guard against a vacuous pass: an empty registry, glob or module
    # filter would leave nothing to run and the crash list empty.
    assert checks != [], "no checks found"
    assert fixtures != [], "no fixture files match #{@fixture_glob}"
    assert callers != [], "no fixture resources found"

    crashes =
      for check <- checks,
          params <- param_variants(check),
          {label, source} <- fixtures ++ callers,
          crash = run_safely(check, source, params),
          do: "#{inspect(check)} #{inspect(params)} on #{label}:\n#{crash}"

    assert crashes == [], Enum.join(crashes, "\n\n")
  end

  defp run_safely(check, source, params) do
    run_check(check, source, params)
    nil
  catch
    kind, reason -> Exception.format(kind, reason, __STACKTRACE__)
  end

  # `[]` (the defaults), then one single-param override per variant.
  defp param_variants(check) do
    overrides =
      for {name, default} <- check.param_defaults(),
          value <- alternative_values(name, default),
          do: [{name, value}]

    [[] | overrides]
  end

  defp alternative_values(_name, default) when is_boolean(default), do: [not default]

  defp alternative_values(name, default),
    do: List.delete(Map.get(@enum_params, name, []), default)

  defp fixture_sources do
    for path <- Path.wildcard(@fixture_glob), do: {path, File.read!(path)}
  end

  defp caller_sources do
    modules = fixture_modules()
    definitions = domain_definitions(modules)

    for resource <- Enum.filter(modules, &Compiled.resource?/1),
        caller <- callers_for(resource) do
      source = caller_source(caller, resource, Map.get(definitions, resource, []))
      {"calls to #{inspect(resource)} from #{caller}", source}
    end
  end

  defp fixture_modules do
    {:ok, modules} = :application.get_key(:ash_credo, :modules)
    Enum.filter(modules, &String.starts_with?(inspect(&1), "AshCredoFixtures."))
  end

  # `%{resource => [{domain, definition}]}` across every fixture domain.
  defp domain_definitions(modules) do
    for domain <- Enum.filter(modules, &Compiled.domain?/1),
        ref <- DomainInfo.resource_references(domain),
        definition <- ref.definitions,
        reduce: %{} do
      acc -> Map.update(acc, ref.resource, [{domain, definition}], &[{domain, definition} | &1])
    end
  end

  # Every resource gets a caller outside any domain; resources with a
  # domain also get a caller named after that domain.
  defp callers_for(resource) do
    case Compiled.domain(resource) do
      {:ok, domain} when not is_nil(domain) -> ["AshCredoSmoke.Caller", inspect(domain)]
      _ -> ["AshCredoSmoke.Caller"]
    end
  end

  defp caller_source(caller, resource_module, definitions) do
    resource = inspect(resource_module)
    {:ok, actions} = Compiled.actions(resource_module)
    {:ok, interfaces} = Compiled.interfaces(resource_module)
    {:ok, calc_interfaces} = Compiled.calculation_interfaces(resource_module)

    calls =
      Enum.flat_map(actions, &action_calls(resource, &1)) ++
        generic_calls(resource) ++
        Enum.map(interfaces ++ calc_interfaces, &bang_call(resource, &1.name)) ++
        Enum.map(definitions, fn {domain, definition} ->
          bang_call(inspect(domain), definition.name)
        end)

    body =
      calls
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {call, index} -> "  def call_#{index}, do: #{call}" end)

    "defmodule #{caller} do\n#{body}\nend\n"
  end

  # The quoted-name call form parses for any atom, including names that
  # end in `?` or contain characters a bare call would reject.
  defp bang_call(module, name), do: "#{module}.#{inspect("#{name}!")}()"

  defp action_calls(resource, %{type: :read, name: name}) do
    [
      "Ash.read!(#{resource}, action: #{inspect(name)})",
      "Ash.read_one(#{resource}, action: #{inspect(name)})",
      "Ash.read_first(#{resource}, action: #{inspect(name)})",
      "Ash.stream!(#{resource}, action: #{inspect(name)})",
      "Ash.get!(#{resource}, 1, action: #{inspect(name)})",
      "Ash.Query.for_read(#{resource}, #{inspect(name)}, %{})"
    ]
  end

  defp action_calls(resource, %{type: :create, name: name}) do
    [
      "Ash.Changeset.for_create(#{resource}, #{inspect(name)}, %{})",
      "Ash.Changeset.for_action(#{resource}, #{inspect(name)}, %{})",
      "Ash.bulk_create([%{}], #{resource}, #{inspect(name)})"
    ]
  end

  defp action_calls(resource, %{type: :update, name: name}) do
    [
      "Ash.Changeset.for_update(%#{resource}{}, #{inspect(name)}, %{})",
      "Ash.Changeset.for_update(Ash.get!(#{resource}, 1), #{inspect(name)}, %{})",
      "(record = Ash.get!(#{resource}, 1); Ash.Changeset.for_update(record, #{inspect(name)}, %{}))",
      "Ash.Changeset.for_action(%#{resource}{}, #{inspect(name)}, %{})",
      "Ash.bulk_update(#{resource}, #{inspect(name)}, %{})"
    ]
  end

  defp action_calls(resource, %{type: :destroy, name: name}) do
    [
      "Ash.Changeset.for_destroy(%#{resource}{}, #{inspect(name)})",
      "Ash.Changeset.for_destroy(Ash.get!(#{resource}, 1), #{inspect(name)})",
      "(record = Ash.get!(#{resource}, 1); Ash.Changeset.for_destroy(record, #{inspect(name)}))",
      "Ash.Changeset.for_action(%#{resource}{}, #{inspect(name)}, %{})",
      "Ash.bulk_destroy(#{resource}, #{inspect(name)}, %{})"
    ]
  end

  defp action_calls(resource, %{type: :action, name: name}) do
    ["Ash.ActionInput.for_action(#{resource}, #{inspect(name)}, %{})"]
  end

  defp generic_calls(resource) do
    [
      "Ash.read!(#{resource})",
      "Ash.get!(#{resource}, 1)",
      "Ash.get!(#{resource}, %{id: 1})",
      "Ash.read!(#{resource}, action: :ash_credo_smoke_unknown)"
    ]
  end
end
