defmodule SootCore.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :soot_core,
      version: @version,
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() != :test,
      deps: deps(),
      description: description(),
      package: package(),
      aliases: aliases(),
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit, :plug, :public_key, :crypto, :ssl],
        plt_core_path: "priv/plts",
        plt_local_path: "priv/plts",
        ignore_warnings: ".dialyzer_ignore.exs",
        list_unused_filters?: true
      ]
    ]
  end

  defp aliases do
    [
      format: "format --migrate",
      credo: "credo --strict"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :public_key, :ssl],
      mod: {SootCore.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp description do
    "Tenants, devices, batches, enrollment, and state machine for the Soot IoT framework."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{}
    ]
  end

  defp deps do
    [
      {:ash, "~> 3.24"},
      {:ash_state_machine, "~> 0.2"},
      {:ash_pki, github: "soot-iot/ash_pki", branch: "main"},
      {:plug, "~> 1.19"},
      {:jason, "~> 1.4"},
      {:nimble_csv, "~> 1.3"},
      {:igniter, "~> 0.6", optional: true},

      # Dev / test
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: [:dev], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:simple_sat, "~> 0.1", only: [:dev, :test]},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false}
    ]
  end
end
