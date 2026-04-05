defmodule AshCredoTest do
  use ExUnit.Case

  @check_dir "lib/ash_credo/check"
  @plugin_file "lib/ash_credo.ex"
  @readme_file "README.md"

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
        Regex.scan(~r/\{AshCredo\.Check\.(\w+)\.(\w+),\s*\[\]\}/, plugin_content)
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

      # Check alphabetical order within each category comment block
      for {_cat_mod, names} <- plugin_by_category do
        assert names == Enum.sort(names),
               "Checks in #{@plugin_file} are not alphabetically sorted. Expected:\n#{inspect(Enum.sort(names))}\nGot:\n#{inspect(names)}"
      end
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

      # Check alphabetical order within each category block in the table
      for {_cat_mod, names} <- readme_by_category do
        assert names == Enum.sort(names),
               "Checks in #{@readme_file} are not alphabetically sorted. Expected:\n#{inspect(Enum.sort(names))}\nGot:\n#{inspect(names)}"
      end
    end
  end
end
