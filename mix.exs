defmodule Membrane.Mixfile do
  use Mix.Project

  @version "0.1.1"

  def project do
    [
      app: :membrane_core,
      version: @version,
      elixir: "~> 1.6",
      elixirc_paths: elixirc_paths(Mix.env()),
      description: "Membrane Multimedia Framework (Core)",
      package: package(),
      name: "Membrane Core",
      source_url: link(),
      docs: docs(),
      preferred_cli_env: [
        espec: :test,
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      test_coverage: [tool: ExCoveralls, test_task: "espec"],
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [], mod: {Membrane, []}]
  end

  defp elixirc_paths(:test), do: ["lib", "spec/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp link do
    "https://github.com/membraneframework/membrane-core"
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_ref: "v#{@version}"
    ]
  end

  defp package do
    [
      maintainers: ["Membrane Team"],
      licenses: ["Apache 2.0"],
      links: %{
        "GitHub" => link(),
        "Membrane Framework Homepage" => "https://membraneframework.org"
      }
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.18", only: :dev, runtime: false},
      {:espec, "~> 1.5", only: :test},
      {:excoveralls, "~> 0.8", only: :test},
      {:qex, "~> 0.3"}
    ]
  end
end
