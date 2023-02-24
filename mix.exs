defmodule Membrane.Mixfile do
  use Mix.Project

  @version "0.11.3"
  @source_ref "v#{@version}"

  def project do
    [
      app: :membrane_core,
      version: @version,
      elixir: "~> 1.12",
      elixirc_paths: elixirc_paths(Mix.env()),
      description: "Membrane Multimedia Framework (Core)",
      dialyzer: dialyzer(),
      package: package(),
      name: "Membrane Core",
      source_url: link(),
      docs: docs(),
      aliases: [docs: ["docs", &copy_assets/1]],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      test_coverage: [tool: ExCoveralls, test_task: "test"],
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp dialyzer() do
    opts = [
      plt_local_path: "priv/plts",
      flags: [:error_handling]
    ]

    if System.get_env("CI") == "true" do
      # Store core PLTs in cacheable directory for CI
      # For development it's better to stick to default, $MIX_HOME based path
      # to allow sharing core PLTs between projects
      [plt_core_path: "priv/plts"] ++ opts
    else
      opts
    end
  end

  defp link do
    "https://github.com/membraneframework/membrane-core"
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "CONTRIBUTING.md",
        "guides/upgrading/v0.11.md",
        LICENSE: [title: "License"]
      ],
      formatters: ["html"],
      source_ref: @source_ref,
      nest_modules_by_prefix: [
        Membrane.Bin,
        Membrane.Element,
        Membrane.Element.CallbackContext,
        Membrane.Pipeline.CallbackContext,
        Membrane.Bin.CallbackContext,
        Membrane.Payload,
        Membrane.Buffer,
        Membrane.StreamFormat,
        Membrane.Event,
        Membrane.EventProtocol,
        Membrane.Testing,
        Membrane.RemoteControlled,
        Membrane.RemoteControlled.Message
      ],
      groups_for_modules: [
        Pipeline: [
          ~r/^Membrane\.Pipeline($|\.)/,
          ~r/^Membrane\.(CrashGroup)($|\.)/,
          ~r/^Membrane\.(RemoteControlled)($|\.)/
        ],
        Bin: [~r/^Membrane\.Bin($|\.)/],
        Element: [
          ~r/^Membrane\.Filter($|\.)/,
          ~r/^Membrane\.FilterAggregator($|\.)/,
          ~r/^Membrane\.Endpoint($|\.)/,
          ~r/^Membrane\.Sink($|\.)/,
          ~r/^Membrane\.Source($|\.)/,
          ~r/^Membrane\.Element($|\.)/
        ],
        Parent: [~r/^Membrane\.(Parent|ChildrenSpec)($|\.)/],
        Child: [~r/^Membrane\.(Child|ChildEntry)($|\.)/],
        Communication: [
          ~r/^Membrane\.(Buffer|Payload|StreamFormat|Event|EventProtocol|ChildNotification|ParentNotification|Pad|KeyframeRequestEvent|RemoteStream)($|\.)/
        ],
        Logging: [~r/^Membrane\.Logger($|\.)/],
        Testing: [~r/^Membrane\.Testing($|\.)/],
        Utils: [
          ~r/^Membrane\.Clock($|\.)/,
          ~r/^Membrane\.Sync($|\.)/,
          ~r/^Membrane\.Time($|\.)/,
          ~r/^Membrane\.Playback($|\.)/,
          ~r/^Membrane\.Telemetry($|\.)/,
          ~r/^Membrane\.ComponentPath($|\.)/,
          ~r/^Membrane\.ResourceGuard($|\.)/,
          ~r/^Membrane\.UtilitySupervisor($|\.)/
        ],
        Errors: [~r/Error$/]
      ]
    ]
  end

  defp copy_assets(_args) do
    File.cp_r("assets", "doc/assets", fn _source, _destination -> true end)
  end

  defp package do
    [
      maintainers: ["Membrane Team"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => link(),
        "Membrane Framework Homepage" => "https://membrane.stream"
      }
    ]
  end

  defp deps do
    [
      {:qex, "~> 0.3"},
      {:telemetry, "~> 1.0"},
      {:bunch, "~> 1.5"},
      {:ratio, "~> 2.0"},
      # Development
      {:ex_doc, "~> 0.28", only: :dev, runtime: false},
      {:makeup_diff, "~> 0.1", only: :dev, runtime: false},
      {:dialyxir, "~> 1.1", only: :dev, runtime: false},
      {:credo, "~> 1.6", only: :dev, runtime: false},
      # Testing
      {:mox, "~> 1.0", only: :test},
      {:junit_formatter, "~> 3.1", only: :test},
      {:excoveralls, "~> 0.14", only: :test}
    ]
  end
end
