defmodule AshCredo.MixProject do
  use Mix.Project

  @version "0.8.0"
  @description "Credo checks for Ash Framework"

  def project do
    [
      app: :ash_credo,
      version: @version,
      description: @description,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
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

  defp aliases do
    [
      lint: ["format --check-formatted", "credo", "lint.no_emdash"]
    ]
  end

  defp elixirc_paths(:test), do: ["lib/", "test/support/"]
  defp elixirc_paths(_), do: ["lib/"]

  defp deps do
    [
      {:credo, "~> 1.7"},
      {:igniter, "~> 0.7", optional: true},
      {:ash, "~> 3.0", only: [:dev, :test], runtime: false},
      {:simple_sat, "~> 0.1", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.3", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:ex_slop, "~> 0.1", only: [:dev, :test], runtime: false},
      {:quokka, "~> 2.12", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      files: ~w(lib .formatter.exs mix.exs README* LICENSE* CHANGELOG*),
      exclude_patterns: [~r/\.expert/],
      links: %{"GitHub" => "https://github.com/leonqadirie/ash_credo"}
    ]
  end

  defp docs do
    [main: "readme", source_ref: "v#{@version}", extras: ["README.md", "CHANGELOG.md", "LICENSE"]]
  end
end
