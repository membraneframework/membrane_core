defmodule Membrane.Mixfile do
  use Mix.Project

  def project do
    [app: :membrane_core,
     version: "0.0.1",
     elixir: "~> 1.3",
     elixirc_paths: elixirc_paths(Mix.env),
     description: "Membrane Multimedia Framework (Core)",
     maintainers: ["Marcin Lewandowski"],
     licenses: ["LGPL"],
     name: "Membrane Core",
     source_url: "https://github.com/radiokit/membrane-core",
     preferred_cli_env: [espec: :test],
     deps: deps]
  end


  def application do
    [applications: [
      :logger,
      :porcelain
    ], mod: {Membrane, []}]
  end


  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_),     do: ["lib",]


  defp deps do
    [
      {:porcelain, "~> 2.0"}
    ]
  end
end
