defmodule Membrane.Mixfile do
  use Mix.Project

  @version "1.2.4"
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
  defp elixirc_paths(:benchmark), do: ["lib", "benchmark"]
  defp elixirc_paths(_env), do: ["lib"]

  defp dialyzer() do
    opts = [
      plt_local_path: "priv/plts",
      flags: [:error_handling, :unmatched_returns]
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
      extras: extras(),
      formatters: ["html"],
      source_ref: @source_ref,
      assets: %{
        "guides/membrane_tutorials/get_started_with_membrane/assets" => "assets",
        "guides/membrane_tutorials/basic_pipeline/assets" => "assets",
        "guides/membrane_tutorials/basic_pipeline_extension/assets" => "assets",
        "guides/membrane_tutorials/create_new_plugin/assets" => "assets",
        "guides/membrane_tutorials/digital_video_introduction/assets" => "assets",
        "guides/membrane_tutorials/h264/assets" => "assets",
        "guides/membrane_tutorials/broadcasting/assets" => "assets",
        "guides/membrane_tutorials/glossary/assets" => "assets"
      },
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
        Membrane.RCPipeline,
        Membrane.RCMessage
      ],
      groups_for_modules: groups_for_modules(),
      groups_for_extras: groups_for_extras()
    ]
  end

  defp extras do
    [
      "README.md",
      "CHANGELOG.md",
      "CONTRIBUTING.md",
      Path.wildcard("guides/**/*.md")
      |> Enum.reject(&(Path.basename(&1) in ["README.md", "index.md", "1_preface.md"]))
      |> Enum.map(&{String.to_atom(&1), [title: reformat_tutorial_title(&1)]}),
      LICENSE: [title: "License"]
    ]
    |> List.flatten()
  end

  defp reformat_tutorial_title(filename) do
    {first_letter, rest} =
      filename
      |> Path.basename()
      |> String.replace(~r/^\d+_/, "")
      |> String.replace("_", " ")
      |> String.trim_trailing(".md")
      |> String.next_grapheme()

    String.upcase(first_letter) <> rest
  end

  defp groups_for_modules do
    [
      Pipeline: [~r/^Membrane\.Pipeline($|\.)/],
      "RC Pipeline": [
        ~r/^Membrane\.(RCPipeline)($|\.)/,
        ~r/^Membrane\.(RCMessage)($|\.)/
      ],
      Bin: [~r/^Membrane\.Bin($|\.)/],
      Element: [
        ~r/^Membrane\.Filter($|\.)/,
        ~r/^Membrane\.Endpoint($|\.)/,
        ~r/^Membrane\.Sink($|\.)/,
        ~r/^Membrane\.Source($|\.)/,
        ~r/^Membrane\.Element($|\.)/
      ],
      "Helper Elements": [
        ~r/^Membrane\.Connector($|\.)/,
        ~r/^Membrane\.Fake($|\.)/,
        ~r/^Membrane\.Debug($|\.)/,
        ~r/^Membrane\.Tee($|\.)/,
        ~r/^Membrane\.Funnel($|\.)/,
        ~r/^Membrane\.FilterAggregator($|\.)/
      ],
      Parent: [~r/^Membrane\.(Parent|ChildrenSpec)($|\.)/],
      Child: [~r/^Membrane\.(Child|ChildEntry)($|\.)/],
      Communication: [
        ~r/^Membrane\.(Buffer|Payload|StreamFormat|Event|EventProtocol|ChildNotification|ParentNotification|Pad|KeyframeRequestEvent|RemoteStream)($|\.)/
      ],
      Logging: [~r/^Membrane\.Logger($|\.)/],
      Telemetry: [~r/^Membrane\.Telemetry($|\.)/],
      Testing: [~r/^Membrane\.Testing($|\.)/],
      Utils: [
        ~r/^Membrane\.Clock($|\.)/,
        ~r/^Membrane\.Sync($|\.)/,
        ~r/^Membrane\.Time($|\.)/,
        ~r/^Membrane\.Playback($|\.)/,
        ~r/^Membrane\.ComponentPath($|\.)/,
        ~r/^Membrane\.ResourceGuard($|\.)/,
        ~r/^Membrane\.UtilitySupervisor($|\.)/
      ],
      Errors: [~r/Error$/]
    ]
  end

  defp groups_for_extras do
    [
      "Get started with Membrane":
        Path.wildcard("guides/membrane_tutorials/get_started_with_membrane/*.md"),
      Ecosystem: Path.wildcard("guides/ecosystem/*.md"),
      "Intro to pipelines": Path.wildcard("guides/membrane_tutorials/basic_pipeline/*.md"),
      "Intro to pipelines - advanced concepts":
        Path.wildcard("guides/membrane_tutorials/basic_pipeline_extension/*.md"),
      "Creating plugins": Path.wildcard("guides/membrane_tutorials/create_new_plugin/*.md"),
      "Useful concepts": Path.wildcard("guides/useful_concepts/*.md"),
      H264: Path.wildcard("guides/membrane_tutorials/h264/*.md"),
      Broadcasting: Path.wildcard("guides/membrane_tutorials/broadcasting/*.md"),
      Glossary: Path.wildcard("guides/membrane_tutorials/glossary/*.md"),
      Upgrading: Path.wildcard("guides/upgrading/*.md")
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
      {:bunch, "~> 1.6"},
      {:ratio, "~> 3.0 or ~> 4.0"},
      # Development
      {:ex_doc, "~> 0.28", only: :dev, runtime: false},
      {:makeup_diff, "~> 0.1", only: :dev, runtime: false},
      {:dialyxir, "~> 1.1", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: :dev, runtime: false},
      # Testing
      {:mox, "~> 1.0", only: :test},
      {:mock, "~> 0.3.8", only: :test},
      {:junit_formatter, "~> 3.1", only: :test},
      {:excoveralls, "~> 0.14", only: :test}
    ]
  end
end
