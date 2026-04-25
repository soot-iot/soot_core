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
      package: package()
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
      {:ash_pki, path: "../ash_pki"},
      {:plug, "~> 1.19"},
      {:jason, "~> 1.4"},
      {:nimble_csv, "~> 1.3"}
    ]
  end
end
