defmodule AshCredo.CheckRegistry do
  @moduledoc false

  @check_dir "lib/ash_credo/check"

  def check_dir, do: @check_dir

  # Discovers all check modules from the filesystem. Returns a sorted list of
  # `{category_module, check_module_name, file_path}` tuples - e.g.
  # `{"Warning", "EmptyDomain", "lib/ash_credo/check/warning/empty_domain.ex"}`.
  # Shared by the registry-consistency tests and the `bench/` suites, so both
  # cover every check file on disk.
  def discover_check_modules do
    Path.wildcard("#{@check_dir}/**/*.ex")
    |> Enum.map(fn path ->
      relative = Path.relative_to(path, @check_dir)
      [category | rest] = Path.split(relative)
      name = rest |> Path.join() |> Path.rootname()
      {to_module_name(category), to_module_name(name), path}
    end)
    |> Enum.sort()
  end

  # The check modules themselves, e.g. `AshCredo.Check.Warning.EmptyDomain`,
  # in `discover_check_modules/0` order.
  def check_modules do
    for {cat, name, _path} <- discover_check_modules(), do: check_module(cat, name)
  end

  # The module for a `{category, name}` pair from `discover_check_modules/0`.
  def check_module(cat, name), do: Module.concat([AshCredo.Check, cat, name])

  # Converts a snake_case filesystem name ("empty_domain") to a module short
  # name ("EmptyDomain"). Also used for category directory names.
  def to_module_name(snake) do
    snake
    |> String.split("_")
    |> Enum.map_join(&String.capitalize/1)
  end
end
