if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.AshCredo.Install do
    @shortdoc "Installs AshCredo and configures .credo.exs"

    @moduledoc """
    #{@shortdoc}

    Adds the `AshCredo` plugin to your `.credo.exs` configuration file.
    If no `.credo.exs` exists, one will be created with sensible defaults.

    ## Example

        mix igniter.install ash_credo --only dev,test
    """

    use Igniter.Mix.Task

    alias Igniter.Code.Common
    alias Igniter.Code.List
    alias Igniter.Code.Map

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :ash_credo,
        only: [:dev, :test],
        dep_opts: [runtime: false],
        example: "mix igniter.install ash_credo --only dev,test"
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

      with {:ok, configs_zipper} <-
             Common.move_to_cursor(zipper, "%{configs: __cursor__()}"),
           {:ok, first_config} <-
             List.move_to_list_item(configs_zipper, fn _ -> true end) do
        Map.put_in_map(
          first_config,
          [:plugins],
          plugin_list,
          fn plugins_zipper ->
            List.prepend_new_to_list(plugins_zipper, plugin_tuple, eq_pred)
          end
        )
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

      For more information, see: https://hexdocs.pm/igniter/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
