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

  # Discovers all check modules from the filesystem.
  # Returns a map of %{category => [short_name, ...]} sorted within each category.
  defp discover_checks do
    Path.wildcard("#{@check_dir}/**/*.ex")
    |> Enum.map(fn path ->
      # e.g. "lib/ash_credo/check/warning/no_actions.ex"
      relative = Path.relative_to(path, @check_dir)
      # e.g. "warning/no_actions.ex"
      [category | rest] = Path.split(relative)
      name = rest |> Path.join() |> Path.rootname()
      {category, name}
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {cat, names} -> {cat, Enum.sort(names)} end)
  end

  # Converts a filesystem name like "no_actions" to a module short name like "NoActions"
  defp to_module_name(snake) do
    snake
    |> String.split("_")
    |> Enum.map_join(&String.capitalize/1)
  end

  # Converts a category dir name to the module category name
  defp to_category_module(cat) do
    to_module_name(cat)
  end

  describe "check registry consistency" do
    test "all checks in #{@plugin_file} match filesystem and are sorted within categories" do
      expected = discover_checks()

      plugin_content = File.read!(@plugin_file)

      # Extract entries like {AshCredo.Check.Warning.NoActions, []}
      plugin_entries =
        Regex.scan(~r/\{AshCredo\.Check\.(\w+)\.(\w+),\s*(?:\[\]|false)\}/, plugin_content)
        |> Enum.map(fn [_full, category, name] -> {category, name} end)

      plugin_by_category =
        plugin_entries
        |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

      # Check completeness: every filesystem check is in the plugin
      for {cat_dir, names} <- expected do
        cat_mod = to_category_module(cat_dir)

        registered = Map.get(plugin_by_category, cat_mod, [])

        for name <- names do
          mod_name = to_module_name(name)

          assert mod_name in registered,
                 "AshCredo.Check.#{cat_mod}.#{mod_name} exists on disk but is missing from #{@plugin_file}"
        end
      end

      # Check no extras: every plugin entry exists on disk
      for {cat_mod, names} <- plugin_by_category do
        cat_dir = Macro.underscore(cat_mod)
        disk_names = Map.get(expected, cat_dir, []) |> Enum.map(&to_module_name/1)

        for name <- names do
          assert name in disk_names,
                 "AshCredo.Check.#{cat_mod}.#{name} is in #{@plugin_file} but has no file in #{@check_dir}/#{cat_dir}/"
        end
      end

      # Enforce canonical category order + alphabetical within each category.
      assert_category_ordering(
        plugin_entries,
        @plugin_file,
        "Checks in #{@plugin_file}"
      )
    end

    test "all checks in #{@readme_file} match filesystem and are sorted within categories" do
      expected = discover_checks()

      readme_content = File.read!(@readme_file)

      # Extract rows like: | `AuthorizerWithoutPolicies` | Warning | ...
      readme_entries =
        Regex.scan(~r/\| `(\w+)` \| (\w+) \|/, readme_content)
        |> Enum.map(fn [_full, name, category] -> {category, name} end)

      readme_by_category =
        readme_entries
        |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

      # Check completeness: every filesystem check is in the README
      for {cat_dir, names} <- expected do
        cat_mod = to_category_module(cat_dir)

        registered = Map.get(readme_by_category, cat_mod, [])

        for name <- names do
          mod_name = to_module_name(name)

          assert mod_name in registered,
                 "AshCredo.Check.#{cat_mod}.#{mod_name} exists on disk but is missing from #{@readme_file}"
        end
      end

      # Check no extras: every README entry exists on disk
      for {cat_mod, names} <- readme_by_category do
        cat_dir = Macro.underscore(cat_mod)
        disk_names = Map.get(expected, cat_dir, []) |> Enum.map(&to_module_name/1)

        for name <- names do
          assert name in disk_names,
                 "`#{name}` is in #{@readme_file} but has no file in #{@check_dir}/#{cat_dir}/"
        end
      end

      # Enforce canonical category order + alphabetical within each category.
      assert_category_ordering(
        readme_entries,
        @readme_file,
        "Checks table in #{@readme_file}"
      )
    end

    # Checks that are enabled by default in `lib/ash_credo.ex` (registered with
    # `[]` instead of `false`). These are intentionally omitted from the
    # "enable all checks" README block.
    @default_on_checks [
      {"Warning", "MissingChangeWrapper"},
      {"Warning", "MissingMacroDirective"}
    ]

    test "\"enable all checks\" block in #{@readme_file} matches filesystem and is sorted within categories" do
      expected = discover_checks()
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

      expected_entries =
        for {cat_dir, names} <- expected,
            cat_mod = to_category_module(cat_dir),
            name <- names,
            entry = {cat_mod, to_module_name(name)},
            entry not in @default_on_checks do
          entry
        end

      # Completeness: every non-default check on disk must be in the block.
      for entry <- expected_entries do
        {cat, name} = entry

        assert entry in enable_all_entries,
               ~s(AshCredo.Check.#{cat}.#{name} exists on disk but is missing from the "enable all checks" block in #{@readme_file})
      end

      # No extras: every entry in the block must exist on disk and must not
      # be one of the default-on checks (which the block explicitly excludes).
      for {cat, name} = entry <- enable_all_entries do
        refute entry in @default_on_checks,
               ~s(AshCredo.Check.#{cat}.#{name} is default-on and should not appear in the "enable all checks" block in #{@readme_file})

        assert entry in expected_entries,
               ~s(AshCredo.Check.#{cat}.#{name} is listed in the "enable all checks" block in #{@readme_file} but has no file in #{@check_dir}/)
      end

      # Enforce canonical category order + alphabetical within each category.
      assert_category_ordering(
        enable_all_entries,
        @readme_file,
        ~s("enable all checks" block in #{@readme_file})
      )
    end

    test "configurable params in #{@readme_file} match filesystem and are sorted within categories" do
      expected = discover_checks()

      # Build expected set of {category_module, check_name, param_name} from disk
      # by calling `param_defaults/0` on each check module (Credo generates this
      # function, returning [] when no params are configured).
      expected_params =
        for {cat_dir, names} <- expected,
            cat_mod = to_category_module(cat_dir),
            name <- names,
            mod_name = to_module_name(name),
            module = Module.concat([AshCredo.Check, cat_mod, mod_name]),
            Code.ensure_loaded?(module),
            {param, _default} <- module.param_defaults() do
          {cat_mod, mod_name, Atom.to_string(param)}
        end

      readme_content = File.read!(@readme_file)

      # Extract rows like: | `Warning.AuthorizeFalse` | `include_non_ash_calls` | ...
      # Only matches the configurable-params table — rows in the main checks
      # table have no dot in the first backticked column.
      readme_param_rows =
        Regex.scan(~r/\| `(\w+)\.(\w+)` \| `(\w+)` \|/, readme_content)
        |> Enum.map(fn [_full, category, name, param] -> {category, name, param} end)

      # Completeness: every disk param appears in the README
      for {cat, name, param} <- expected_params do
        assert {cat, name, param} in readme_param_rows,
               "AshCredo.Check.#{cat}.#{name} defines param :#{param} but it is missing from the configurable-params table in #{@readme_file}"
      end

      # No extras: every README row exists on disk
      for {cat, name, param} <- readme_param_rows do
        assert {cat, name, param} in expected_params,
               "`#{cat}.#{name}` / `#{param}` is listed in #{@readme_file} but the check has no such param in its `param_defaults`"
      end

      # Enforce canonical category order, alphabetical by check name within
      # each category, and param rows of the same check in `param_defaults/0`
      # source order.
      category_index = Map.new(Enum.with_index(@category_order))

      param_order_index =
        for {cat_dir, names} <- expected,
            cat_mod = to_category_module(cat_dir),
            name <- names,
            mod_name = to_module_name(name),
            module = Module.concat([AshCredo.Check, cat_mod, mod_name]),
            Code.ensure_loaded?(module),
            {{param, _default}, idx} <- Enum.with_index(module.param_defaults()),
            into: %{} do
          {{cat_mod, mod_name, Atom.to_string(param)}, idx}
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
  end

  # Asserts that `entries` (a list of `{category, name}` tuples in document
  # order) follows the canonical category order and is alphabetical within
  # each category. Used for both the plugin file and the main checks table.
  defp assert_category_ordering(entries, _file, label) do
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
