defmodule AshCredo.MixProject do
  use Mix.Project

  @version "0.1.0"
  @description "Credo checks for Ash Framework"

  def project do
    [
      app: :ash_credo,
      version: @version,
      description: @description,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      package: package(),
      docs: docs(),
      source_url: "https://github.com/leonqadirie/ash_credo",
      homepage_url: "https://github.com/leonqadirie/ash_credo"
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib/", "test/support/"]
  defp elixirc_paths(_), do: ["lib/"]

  defp deps do
    [
      {:credo, "~> 1.7"},
      {:igniter, "~> 0.7", optional: true},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:quokka, "~> 2.12", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      files: ~w(lib .formatter.exs mix.exs README* LICENSE* CHANGELOG*),
      links: %{"GitHub" => "https://github.com/leonqadirie/ash_credo"}
    ]
  end

  defp docs do
    [main: "readme", source_ref: "v#{@version}", extras: ["README.md"]]
  end
end
