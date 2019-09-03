defmodule Membrane.Mixfile do
  use Mix.Project

  @version "0.3.2"
  @source_ref "v#{@version}"

  def project do
    [
      app: :membrane_core,
      version: @version,
      elixir: "~> 1.7",
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

  defp elixirc_paths(:test), do: ["lib", "spec/support", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp link do
    "https://github.com/membraneframework/membrane-core"
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_ref: @source_ref,
      nest_modules_by_prefix: [
        Membrane.Pipeline,
        Membrane.Element,
        Membrane.Element.CallbackContext,
        Membrane.Payload,
        Membrane.Buffer,
        Membrane.Caps,
        Membrane.Event,
        Membrane.EventProtocol,
        Membrane.Log,
        Membrane.Testing
      ],
      groups_for_modules: [
        Pipeline: [~r/^Membrane.Pipeline.*/],
        Element: [
          ~r/^Membrane.Element$/,
          ~r/^Membrane.Element(?!\.CallbackContext)\..*/,
          ~r/^Membrane.Core.InputBuffer/
        ],
        "Callback contexts": [~r/^Membrane.Element.CallbackContext.*/],
        Communication: [
          ~r/^Membrane.(Buffer|Payload|Caps|Event|Notification).*/
        ],
        Logging: [~r/^Membrane.Log.*/],
        Testing: [~r/^Membrane.Testing.*/],
        Utils: [~r/^Membrane.(Time|Helper).*/]
      ]
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
      {:ex_doc, "~> 0.19", only: :dev, runtime: false},
      {:espec, "~> 1.7", only: :test},
      {:excoveralls, "~> 0.8", only: :test},
      {:qex, "~> 0.3"},
      {:dialyxir, "~> 1.0.0-rc.4", only: [:dev], runtime: false},
      {:bunch, "~> 1.1"}
    ]
  end
end
