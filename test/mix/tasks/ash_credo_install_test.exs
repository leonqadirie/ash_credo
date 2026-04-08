defmodule Mix.Tasks.AshCredo.InstallTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  alias Mix.Tasks.AshCredo.Install, as: AshCredoInstall

  describe "installer metadata" do
    test "installs ash_credo as a dev/test, non-runtime dependency" do
      info = AshCredoInstall.info([], nil)

      assert info.only == [:dev, :test]
      assert info.dep_opts[:runtime] == false
    end
  end

  describe "with no existing .credo.exs" do
    test "creates .credo.exs with AshCredo plugin" do
      test_project()
      |> Igniter.compose_task("ash_credo.install")
      |> assert_creates(".credo.exs")
    end
  end

  describe "with existing .credo.exs" do
    test "adds AshCredo to existing plugins list" do
      test_project(
        files: %{
          ".credo.exs" => """
          %{
            configs: [
              %{
                name: "default",
                plugins: [{SomeOtherPlugin, []}]
              }
            ]
          }
          """
        }
      )
      |> Igniter.compose_task("ash_credo.install")
      |> assert_has_patch(".credo.exs", """
      + |      plugins: [{AshCredo, []}, {SomeOtherPlugin, []}]
      """)
    end

    test "adds plugins key when missing" do
      test_project(
        files: %{
          ".credo.exs" => """
          %{
            configs: [
              %{
                name: "default",
                checks: %{
                  enabled: []
                }
              }
            ]
          }
          """
        }
      )
      |> Igniter.compose_task("ash_credo.install")
      |> assert_has_patch(".credo.exs", """
      + |      plugins: [{AshCredo, []}]
      """)
    end

    test "adds to empty plugins list" do
      test_project(
        files: %{
          ".credo.exs" => """
          %{
            configs: [
              %{
                name: "default",
                plugins: []
              }
            ]
          }
          """
        }
      )
      |> Igniter.compose_task("ash_credo.install")
      |> assert_has_patch(".credo.exs", """
      + |      plugins: [{AshCredo, []}]
      """)
    end

    test "is idempotent when AshCredo already present" do
      test_project(
        files: %{
          ".credo.exs" => """
          %{
            configs: [
              %{
                name: "default",
                plugins: [{AshCredo, []}]
              }
            ]
          }
          """
        }
      )
      |> Igniter.compose_task("ash_credo.install")
      |> assert_unchanged()
    end

    test "is idempotent when AshCredo present among other plugins" do
      test_project(
        files: %{
          ".credo.exs" => """
          %{
            configs: [
              %{
                name: "default",
                plugins: [{PluginA, []}, {AshCredo, []}, {PluginB, []}]
              }
            ]
          }
          """
        }
      )
      |> Igniter.compose_task("ash_credo.install")
      |> assert_unchanged()
    end

    test "prepends with correct commas in a multiline plugins list" do
      test_project(
        files: %{
          ".credo.exs" => """
          %{
            configs: [
              %{
                name: "default",
                plugins: [
                  {PluginA, []},
                  {PluginB, []}
                ]
              }
            ]
          }
          """
        }
      )
      |> Igniter.compose_task("ash_credo.install")
      |> assert_has_patch(".credo.exs", """
      + |        {AshCredo, []},
      """)
    end

    test "only modifies first config when multiple configs exist" do
      test_project(
        files: %{
          ".credo.exs" => """
          %{
            configs: [
              %{
                name: "default",
                plugins: [{SomePlugin, []}]
              },
              %{
                name: "other",
                plugins: []
              }
            ]
          }
          """
        }
      )
      |> Igniter.compose_task("ash_credo.install")
      |> assert_has_patch(".credo.exs", """
      + |      plugins: [{AshCredo, []}, {SomePlugin, []}]
      """)
    end

    test "works with a realistic .credo.exs from mix credo gen.config" do
      test_project(
        files: %{
          ".credo.exs" => """
          %{
            configs: [
              %{
                name: "default",
                files: %{
                  included: ["lib/", "src/", "web/", "apps/"],
                  excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/"]
                },
                plugins: [],
                requires: [],
                strict: false,
                parse_timeout: 5000,
                color: true,
                checks: %{
                  enabled: [
                    {Credo.Check.Consistency.TabsOrSpaces, []}
                  ],
                  disabled: []
                }
              }
            ]
          }
          """
        }
      )
      |> Igniter.compose_task("ash_credo.install")
      |> assert_has_patch(".credo.exs", """
      + |      plugins: [{AshCredo, []}],
      """)
    end
  end
end
