if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.AshCredo.Install do
    @shortdoc "Installs AshCredo and configures .credo.exs"

    @moduledoc """
    #{@shortdoc}

    Adds the `AshCredo` plugin to your `.credo.exs` configuration file.
    If no `.credo.exs` exists, one will be created with sensible defaults.

    ## Example

        mix igniter.install ash_credo
    """

    use Igniter.Mix.Task

    alias Igniter.Code.Common
    alias Igniter.Code.List
    alias Igniter.Code.Map

    @manual_install_warning """
    Could not automatically add the AshCredo plugin to .credo.exs - its
    `configs:` value is not a literal list this installer can navigate.

    Add the plugin to your config manually:

        %{
          configs: [
            %{
              name: "default",
              plugins: [{AshCredo, []}]
            }
          ]
        }
    """

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :ash_credo,
        only: [:dev, :test],
        dep_opts: [runtime: false],
        example: "mix igniter.install ash_credo"
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      Igniter.create_or_update_elixir_file(
        igniter,
        ".credo.exs",
        default_credo_config(),
        &update_credo_config/1
      )
    end

    defp update_credo_config(zipper) do
      plugin_tuple = Sourceror.parse_string!("{AshCredo, []}")
      plugin_list = Sourceror.parse_string!("[{AshCredo, []}]")

      eq_pred = fn existing_zipper, new_node ->
        Sourceror.to_string(Sourceror.Zipper.node(existing_zipper)) ==
          Sourceror.to_string(new_node)
      end

      # Each step returns `:error` when the config is not a literal it can
      # navigate. Igniter's updater contract has no clause for a bare
      # `:error`, so without the `else` that crashes the whole install;
      # degrade to a warning with manual instructions instead.
      with {:ok, configs_zipper} <-
             Common.move_to_cursor(zipper, "%{configs: __cursor__()}"),
           {:ok, first_config} <-
             List.move_to_list_item(configs_zipper, fn _ -> true end),
           {:ok, updated_config} <-
             Map.put_in_map(
               first_config,
               [:plugins],
               plugin_list,
               fn plugins_zipper ->
                 List.prepend_new_to_list(plugins_zipper, plugin_tuple, eq_pred)
               end
             ) do
        {:ok, updated_config}
      else
        _ -> {:warning, @manual_install_warning}
      end
    end

    defp default_credo_config do
      """
      %{
        configs: [
          %{
            name: "default",
            plugins: [{AshCredo, []}]
          }
        ]
      }
      """
    end
  end
else
  defmodule Mix.Tasks.AshCredo.Install do
    @shortdoc "Installs AshCredo and configures .credo.exs | Install `igniter` to use"

    @moduledoc """
    #{@shortdoc}

    This task requires the `igniter` package to be installed.
    """

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      The task 'ash_credo.install' requires igniter. Please install igniter and try again.

      For more information, see: https://igniter.hexdocs.pm/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
