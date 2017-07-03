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
     source_url: "https://bitbucket.org/radiokit/membrane-core",
     preferred_cli_env: [espec: :test, "coveralls": :test, "coveralls.detail": :test, "coveralls.post": :test, "coveralls.html": :test],
     test_coverage: [tool: ExCoveralls, test_task: "espec"],
     deps: deps()]
  end


  def application do
    [applications: [
    ], mod: {Membrane, []}]
  end


  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_),     do: ["lib",]


  defp deps do
    [
      {:espec,       "~> 1.1",  only: :test},
      {:excoveralls, "~> 0.6",  only: :test},
      {:ex_doc,      "~> 0.14", only: :dev},
    ]
  end
end
