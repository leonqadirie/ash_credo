defmodule AshCredo.CheckArchitectureTest do
  @moduledoc """
  Architectural invariants over the check modules, enforced as tests rather
  than as runtime Credo self-checks.

  The compiled-introspection boundary (only `Compiled` may call Ash's runtime
  introspection) is enforced structurally by the `calls.forbidden` policy in
  `.reach.exs`. The wrapper obligation is enforced structurally by the
  `AshCredo.CompiledCheck` base. This test closes the residual gap that the
  base alone leaves: a new check could still `use Credo.Check` directly and
  call `Compiled`, bypassing the guard. It also pins the one convention every
  check shares - the `:ash` tag - which no base enforces.
  """
  use ExUnit.Case, async: true

  alias AshCredo.Introspection.Aliases

  @check_glob "lib/ash_credo/check/**/*.ex"
  @compiled_segments [:AshCredo, :Introspection, :Compiled]

  # The category/priority vocabularies Credo recognises. A typo here
  # (`category: :warnings`) otherwise only surfaces as a Credo crash at runtime.
  @categories ~w(consistency design readability refactor warning)a
  @priorities ~w(higher high normal low lower)a

  # `{module, references_compiled?}` for every check module on disk. Driven by
  # the filesystem rather than `:application.get_key/2`, whose module list lags
  # a freshly added file, so a new check is covered the moment its file exists.
  defp check_files do
    for path <- Path.wildcard(@check_glob),
        {module, refs?} = parse_check(path),
        Code.ensure_loaded?(module),
        function_exported?(module, :run, 2),
        do: {module, refs?}
  end

  defp parse_check(path) do
    ast = path |> File.read!() |> Code.string_to_quoted!()
    {defmodule_name(ast), references_compiled?(ast)}
  end

  defp defmodule_name(ast) do
    {_ast, name} =
      Macro.prewalk(ast, nil, fn
        {:defmodule, _, [{:__aliases__, _, segs}, _]} = node, nil -> {node, Module.concat(segs)}
        node, acc -> {node, acc}
      end)

    name
  end

  # True if the source makes a qualified call whose module resolves to
  # `AshCredo.Introspection.Compiled`. Resolution goes through the project's own
  # `Aliases` helper, so every alias form the checks use is covered: plain,
  # `:as` rename, grouped (`alias X.{Compiled, Aliases}`), and a parent alias
  # with a relative call (`alias X; X.Compiled.f(...)`).
  defp references_compiled?(ast) do
    aliases = collect_aliases(ast)

    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {{:., _, [{:__aliases__, _, segs}, fun]}, _, _} = node, acc when is_atom(fun) ->
          {node, acc or Aliases.expand_alias(segs, aliases) == @compiled_segments}

        node, acc ->
          {node, acc}
      end)

    found?
  end

  defp collect_aliases(ast) do
    {_ast, entries} =
      Macro.prewalk(ast, [], fn
        {:alias, _, _} = node, acc -> {node, acc ++ Aliases.alias_entries(node)}
        node, acc -> {node, acc}
      end)

    entries
  end

  test "every check that depends on Compiled uses the AshCredo.CompiledCheck base" do
    offenders =
      for {module, true} <- check_files(),
          not function_exported?(module, :run_compiled, 2),
          do: module

    assert offenders == [],
           """
           These checks reference AshCredo.Introspection.Compiled but do not
           `use AshCredo.CompiledCheck`, so the Ash-availability guard is
           missing - they can crash or silently no-op when the host project is
           uncompiled. Convert them to the base: #{inspect(offenders)}
           """
  end

  test "every check is tagged :ash" do
    untagged = for {module, _} <- check_files(), :ash not in module.tags(), do: module

    assert untagged == [],
           "These AshCredo checks are missing the :ash tag (needed for " <>
             "`mix credo --only ash`): #{inspect(untagged)}"
  end

  test "every check declares a known category" do
    offenders =
      for {module, _} <- check_files(),
          module.category() not in @categories,
          do: {module, module.category()}

    assert offenders == [],
           "These checks declare an unknown category (Credo will not group " <>
             "them and may crash): #{inspect(offenders)}"
  end

  test "every check declares a known base_priority" do
    offenders =
      for {module, _} <- check_files(),
          module.base_priority() not in @priorities,
          do: {module, module.base_priority()}

    assert offenders == [],
           "These checks declare an unknown base_priority: #{inspect(offenders)}"
  end

  describe "references_compiled?/1 resolves every alias form" do
    test "direct fully-qualified call" do
      assert references_compiled?(
               quoted("def run(x), do: AshCredo.Introspection.Compiled.inspect_module(x)")
             )
    end

    test "alias with :as rename" do
      assert references_compiled?(
               quoted("""
               alias AshCredo.Introspection.Compiled, as: CI
               def run(x), do: CI.action(x, :read)
               """)
             )
    end

    test "grouped alias" do
      assert references_compiled?(
               quoted("""
               alias AshCredo.Introspection.{Compiled, Aliases}
               def run(x), do: Compiled.inspect_module(x)
               """)
             )
    end

    test "parent alias with a relative call" do
      assert references_compiled?(
               quoted("""
               alias AshCredo.Introspection
               def run(x), do: Introspection.Compiled.inspect_module(x)
               """)
             )
    end

    test "no Compiled reference" do
      refute references_compiled?(
               quoted("""
               alias AshCredo.Orchestration
               def run(sf, p), do: Orchestration.flat_map_resource_context(sf, p, fn _, _ -> [] end)
               """)
             )
    end

    test "grouped alias of siblings, not Compiled" do
      refute references_compiled?(
               quoted("""
               alias AshCredo.Introspection.{Aliases, Block}
               def run(x), do: Aliases.expand_alias(x, [])
               """)
             )
    end
  end

  defp quoted(src), do: Code.string_to_quoted!("defmodule Probe do\n#{src}\nend")
end
