defmodule AshCredoTest do
  use ExUnit.Case

  @check_dir "lib/ash_credo/check"
  @plugin_file "lib/ash_credo.ex"
  @readme_file "README.md"

  # Canonical category order applied to every place that lists checks:
  # the main checks table, the configurable-params table, and the plugin
  # file's `extra` config. Categories not yet used in the codebase are
  # tolerated (they simply contribute zero rows).
  @category_order ["Warning", "Refactor", "Design", "Consistency", "Readability"]

  # Checks that are enabled by default in `lib/ash_credo.ex` (registered with
  # `[]` instead of `false`). These are intentionally omitted from the
  # "enable all checks" README block.
  @default_on_checks [
    {"Warning", "MissingChangeWrapper"},
    {"Warning", "MissingMacroDirective"}
  ]

  # A check requires a compiled project iff it aliases
  # `AshCredo.Introspection.Compiled` at module level. Anchored to line start
  # (plus optional leading whitespace) so comment/docstring mentions don't
  # produce false positives.
  @compiled_alias_regex ~r/^\s*alias AshCredo\.Introspection\.Compiled\b/m

  # Inline annotation used in the main checks table in README.md. Matched
  # loosely because some rows end with `.**` and others continue with
  # ` and **configurable**`.
  @compiled_annotation "**Requires compiled project"

  # Discovers all check modules from the filesystem. Returns a sorted list of
  # `{category_module, check_module_name, file_path}` tuples - e.g.
  # `{"Warning", "NoActions", "lib/ash_credo/check/warning/no_actions.ex"}`.
  defp discover_check_modules do
    Path.wildcard("#{@check_dir}/**/*.ex")
    |> Enum.map(fn path ->
      relative = Path.relative_to(path, @check_dir)
      [category | rest] = Path.split(relative)
      name = rest |> Path.join() |> Path.rootname()
      {to_module_name(category), to_module_name(name), path}
    end)
    |> Enum.sort()
  end

  # Source of truth for "requires a compiled project": every check file whose
  # source aliases `AshCredo.Introspection.Compiled`.
  defp compiled_check_modules do
    for {cat, name, path} <- discover_check_modules(),
        File.read!(path) =~ @compiled_alias_regex do
      {cat, name}
    end
  end

  # Converts a snake_case filesystem name ("no_actions") to a module short
  # name ("NoActions"). Also used for category directory names.
  defp to_module_name(snake) do
    snake
    |> String.split("_")
    |> Enum.map_join(&String.capitalize/1)
  end

  describe "check registry consistency" do
    test "all checks in #{@plugin_file} match filesystem and are sorted within categories" do
      expected = for {cat, name, _path} <- discover_check_modules(), do: {cat, name}
      plugin_content = File.read!(@plugin_file)

      # Extract entries like {AshCredo.Check.Warning.NoActions, []}
      plugin_entries =
        Regex.scan(~r/\{AshCredo\.Check\.(\w+)\.(\w+),\s*(?:\[\]|false)\}/, plugin_content)
        |> Enum.map(fn [_full, category, name] -> {category, name} end)

      assert_set_equality(
        expected,
        plugin_entries,
        fn {cat, name} ->
          "AshCredo.Check.#{cat}.#{name} exists on disk but is missing from #{@plugin_file}"
        end,
        fn {cat, name} ->
          "AshCredo.Check.#{cat}.#{name} is in #{@plugin_file} but has no file in #{@check_dir}/"
        end
      )

      assert_category_ordering(plugin_entries, "Checks in #{@plugin_file}")
    end

    test "all checks in #{@readme_file} match filesystem and are sorted within categories" do
      expected = for {cat, name, _path} <- discover_check_modules(), do: {cat, name}
      readme_content = File.read!(@readme_file)

      # Extract rows like: | `AuthorizerWithoutPolicies` | Warning | ...
      readme_entries =
        Regex.scan(~r/\| `(\w+)` \| (\w+) \|/, readme_content)
        |> Enum.map(fn [_full, name, category] -> {category, name} end)

      assert_set_equality(
        expected,
        readme_entries,
        fn {cat, name} ->
          "AshCredo.Check.#{cat}.#{name} exists on disk but is missing from #{@readme_file}"
        end,
        fn {cat, name} ->
          "`#{name}` is in #{@readme_file} but has no file under `#{cat}` in #{@check_dir}/"
        end
      )

      assert_category_ordering(readme_entries, "Checks table in #{@readme_file}")
    end

    test "\"enable all checks\" block in #{@readme_file} matches filesystem and is sorted within categories" do
      expected =
        for {cat, name, _path} <- discover_check_modules(),
            {cat, name} not in @default_on_checks do
          {cat, name}
        end

      readme_content = File.read!(@readme_file)

      # Isolate the code block that follows the "To enable **all** checks at
      # once" marker so we don't pick up the partial example higher up in the
      # README.
      enable_all_block =
        case Regex.run(
               ~r/To enable \*\*all\*\* checks at once.*?```elixir\s*(.*?)```/s,
               readme_content,
               capture: :all_but_first
             ) do
          [block] ->
            block

          _ ->
            flunk(~s(Could not find the "enable all checks" elixir block in #{@readme_file}))
        end

      enable_all_entries =
        Regex.scan(~r/\{AshCredo\.Check\.(\w+)\.(\w+),\s*\[\]\}/, enable_all_block)
        |> Enum.map(fn [_full, category, name] -> {category, name} end)

      assert_set_equality(
        expected,
        enable_all_entries,
        fn {cat, name} ->
          ~s(AshCredo.Check.#{cat}.#{name} exists on disk but is missing from the "enable all checks" block in #{@readme_file})
        end,
        fn {cat, name} = entry ->
          if entry in @default_on_checks do
            ~s(AshCredo.Check.#{cat}.#{name} is default-on and should not appear in the "enable all checks" block in #{@readme_file})
          else
            ~s(AshCredo.Check.#{cat}.#{name} is listed in the "enable all checks" block in #{@readme_file} but has no file in #{@check_dir}/)
          end
        end
      )

      assert_category_ordering(
        enable_all_entries,
        ~s("enable all checks" block in #{@readme_file})
      )
    end

    test "compiled-project bullet list in #{@readme_file} matches filesystem" do
      compiled = compiled_check_modules()
      readme_content = File.read!(@readme_file)

      bullet_block =
        case Regex.run(
               ~r/## Checks that require a compiled project.*?\n((?:- `[\w.]+`\n)+)/s,
               readme_content,
               capture: :all_but_first
             ) do
          [block] ->
            block

          _ ->
            flunk(
              ~s(Could not find the "Checks that require a compiled project" bullet list in #{@readme_file})
            )
        end

      bullet_entries =
        Regex.scan(~r/- `(\w+)\.(\w+)`/, bullet_block)
        |> Enum.map(fn [_full, category, name] -> {category, name} end)

      assert_set_equality(
        compiled,
        bullet_entries,
        fn {cat, name} ->
          ~s(AshCredo.Check.#{cat}.#{name} aliases `AshCredo.Introspection.Compiled` but is missing from the bullet list under "## Checks that require a compiled project" in #{@readme_file})
        end,
        fn {cat, name} ->
          ~s(`#{cat}.#{name}` is listed under "## Checks that require a compiled project" in #{@readme_file} but its source does not alias `AshCredo.Introspection.Compiled`)
        end
      )
    end

    test "compiled-project inline annotations in #{@readme_file} match filesystem" do
      compiled = compiled_check_modules()
      readme_content = File.read!(@readme_file)

      # Capture each row of the main checks table along with its description
      # column. Rows look like:
      #   | `CheckName` | Category | Priority | Default | Description |
      annotated_entries =
        Regex.scan(
          ~r/\| `(\w+)` \| (\w+) \| \w+ \| \w+ \| ([^|]+) \|/,
          readme_content
        )
        |> Enum.filter(fn [_full, _name, _cat, desc] ->
          String.contains?(desc, @compiled_annotation)
        end)
        |> Enum.map(fn [_full, name, category, _desc] -> {category, name} end)

      assert_set_equality(
        compiled,
        annotated_entries,
        fn {cat, name} ->
          ~s(AshCredo.Check.#{cat}.#{name} aliases `AshCredo.Introspection.Compiled` but its row in the main checks table in #{@readme_file} is missing the `#{@compiled_annotation}` annotation)
        end,
        fn {cat, name} ->
          ~s(`#{cat}.#{name}` is annotated `#{@compiled_annotation}` in the main checks table in #{@readme_file} but its source does not alias `AshCredo.Introspection.Compiled`)
        end
      )
    end

    test "configurable params in #{@readme_file} match filesystem and are sorted within categories" do
      # Build expected set of {category_module, check_name, param_name} from disk
      # by calling `param_defaults/0` on each check module (Credo generates this
      # function, returning [] when no params are configured).
      expected_params =
        for {cat, name, _path} <- discover_check_modules(),
            module = Module.concat([AshCredo.Check, cat, name]),
            Code.ensure_loaded?(module),
            {param, _default} <- module.param_defaults() do
          {cat, name, Atom.to_string(param)}
        end

      readme_content = File.read!(@readme_file)

      # Extract rows like: | `Warning.AuthorizeFalse` | `include_non_ash_calls` | ...
      # Only matches the configurable-params table - rows in the main checks
      # table have no dot in the first backticked column.
      readme_param_rows =
        Regex.scan(~r/\| `(\w+)\.(\w+)` \| `(\w+)` \|/, readme_content)
        |> Enum.map(fn [_full, category, name, param] -> {category, name, param} end)

      assert_set_equality(
        expected_params,
        readme_param_rows,
        fn {cat, name, param} ->
          "AshCredo.Check.#{cat}.#{name} defines param :#{param} but it is missing from the configurable-params table in #{@readme_file}"
        end,
        fn {cat, name, param} ->
          "`#{cat}.#{name}` / `#{param}` is listed in #{@readme_file} but the check has no such param in its `param_defaults`"
        end
      )

      # Enforce canonical category order, alphabetical by check name within
      # each category, and param rows of the same check in `param_defaults/0`
      # source order.
      category_index = Map.new(Enum.with_index(@category_order))

      param_order_index =
        for {cat, name, _path} <- discover_check_modules(),
            module = Module.concat([AshCredo.Check, cat, name]),
            Code.ensure_loaded?(module),
            {{param, _default}, idx} <- Enum.with_index(module.param_defaults()),
            into: %{} do
          {{cat, name, Atom.to_string(param)}, idx}
        end

      for {cat, _name, _param} <- readme_param_rows do
        assert Map.has_key?(category_index, cat),
               "Configurable-params table in #{@readme_file} references unknown category `#{cat}`. Known categories: #{inspect(@category_order)}"
      end

      expected_row_order =
        Enum.sort_by(readme_param_rows, fn {cat, name, _param} = row ->
          {Map.fetch!(category_index, cat), name, Map.fetch!(param_order_index, row)}
        end)

      assert readme_param_rows == expected_row_order, """
      Configurable-params table in #{@readme_file} is not in the expected order.

      Rules:
        1. Category sequence must match #{inspect(@category_order)}.
        2. Check names within a category must be alphabetical.
        3. Param rows of the same check must match the order in `param_defaults/0`.

      Expected:
      #{inspect(expected_row_order, pretty: true)}

      Got:
      #{inspect(readme_param_rows, pretty: true)}
      """
    end

    test "declared category matches directory for all checks" do
      for {cat, name, _path} <- discover_check_modules() do
        module = Module.concat([AshCredo.Check, cat, name])
        assert Code.ensure_loaded?(module), "Could not load #{inspect(module)}"

        declared_cat = module.category() |> Atom.to_string() |> to_module_name()

        assert declared_cat == cat,
               "AshCredo.Check.#{cat}.#{name} is in the `#{String.downcase(cat)}` directory but declares `category: :#{module.category()}`"
      end
    end

    test "every check has a corresponding test file" do
      expected =
        for {cat, name, _path} <- discover_check_modules(), do: {cat, name}

      actual =
        Path.wildcard("test/ash_credo/check/**/*_test.exs")
        |> Enum.map(fn path ->
          relative = Path.relative_to(path, "test/ash_credo/check")
          [category | rest] = Path.split(relative)
          name = rest |> Path.join() |> Path.rootname() |> String.trim_trailing("_test")
          {to_module_name(category), to_module_name(name)}
        end)
        |> Enum.sort()

      assert_set_equality(
        expected,
        actual,
        fn {cat, name} ->
          "AshCredo.Check.#{cat}.#{name} has no corresponding test file"
        end,
        fn {cat, name} ->
          "Test file exists for #{cat}.#{name} but no check module in #{@check_dir}/"
        end
      )
    end

    test "all checks include the :ash tag" do
      for {cat, name, _path} <- discover_check_modules() do
        module = Module.concat([AshCredo.Check, cat, name])
        assert Code.ensure_loaded?(module), "Could not load #{inspect(module)}"

        assert :ash in module.tags(),
               "AshCredo.Check.#{cat}.#{name} is missing the `:ash` tag (has tags: #{inspect(module.tags())})"
      end
    end

    test ":security tag implies category: :warning" do
      for {cat, name, _path} <- discover_check_modules(),
          module = Module.concat([AshCredo.Check, cat, name]),
          Code.ensure_loaded?(module),
          :security in module.tags() do
        assert module.category() == :warning,
               "AshCredo.Check.#{cat}.#{name} has the `:security` tag but declares `category: :#{module.category()}` (security checks must be warnings)"
      end
    end
  end

  # Asserts that `expected` and `actual` (lists of tuples) contain the same
  # set of entries. On mismatch, reports all missing and extra items at once
  # using the caller-supplied formatters.
  defp assert_set_equality(expected, actual, format_missing, format_extra) do
    expected_set = MapSet.new(expected)
    actual_set = MapSet.new(actual)

    missing =
      expected_set
      |> MapSet.difference(actual_set)
      |> Enum.sort()
      |> Enum.map(format_missing)

    extra =
      actual_set
      |> MapSet.difference(expected_set)
      |> Enum.sort()
      |> Enum.map(format_extra)

    case missing ++ extra do
      [] -> :ok
      errors -> flunk(Enum.join(errors, "\n"))
    end
  end

  # Asserts that `entries` (a list of `{category, name}` tuples in document
  # order) follows the canonical category order and is alphabetical within
  # each category.
  defp assert_category_ordering(entries, label) do
    category_index = Map.new(Enum.with_index(@category_order))

    for {cat, _name} <- entries do
      assert Map.has_key?(category_index, cat),
             "#{label} references unknown category `#{cat}`. Known categories: #{inspect(@category_order)}"
    end

    expected_order =
      Enum.sort_by(entries, fn {cat, name} ->
        {Map.fetch!(category_index, cat), name}
      end)

    assert entries == expected_order, """
    #{label} is not in the expected order.

    Rules:
      1. Category sequence must match #{inspect(@category_order)}.
      2. Names within a category must be alphabetical.

    Expected:
    #{inspect(expected_order, pretty: true)}

    Got:
    #{inspect(entries, pretty: true)}
    """
  end
end
