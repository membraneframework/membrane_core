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
      logo: "assets/logo.svg",
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
      Path.wildcard("guides/upgrading/*.md"),
      Path.wildcard("guides/useful_concepts/*.md"),
      Path.wildcard("guides/membrane_demo/*")
      |> Enum.filter(&File.dir?/1)
      |> Enum.reject(&(Path.basename(&1) == "livebooks"))
      |> Enum.map(&get_demo_external_extra/1),
      Path.wildcard("guides/membrane_demo/livebooks/*/*.livemd"),
      Path.wildcard("guides/membrane_tutorials/**/*.md")
      |> Enum.reject(&(Path.basename(&1) in ["README.md", "index.md", "1_preface.md"]))
      |> Enum.map(&{String.to_atom(&1), [title: reformat_tutorial_title(&1)]}),
      Path.wildcard("guides/packages/*.md")
      |> Enum.map(&{String.to_atom(&1), [title: reformat_tutorial_title(&1)]}),
      LICENSE: [title: "License"]
    ]
    |> List.flatten()
  end

  defp get_demo_external_extra(demo_path) do
    demos_url = "https://github.com/membraneframework/membrane_demo/tree/master"

    demo_title =
      demo_path
      |> Path.join("README.md")
      |> File.read!()
      |> String.split("\n")
      |> List.first()
      |> String.trim_leading("#")
      |> String.trim_leading()
      |> String.to_atom()

    demo_url =
      Path.join(demos_url, Path.basename(demo_path))

    {demo_title, [url: demo_url]}
  end

  defp reformat_tutorial_title(filename) do
    filename
    |> Path.basename()
    |> String.replace(~r/^\d+_/, "")
    |> String.replace("_", " ")
    |> String.trim_trailing(".md")
    |> :string.titlecase()
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
      "Useful concepts": Path.wildcard("guides/useful_concepts/*.md"),
      "Pipelines 101": Path.wildcard("guides/membrane_tutorials/basic_pipeline/*.md"),
      "Our demos": ~r"(https://github.com/membraneframework/membrane_demo|.*\.livemd)",
      "Packages in our ecosystem": Path.wildcard("guides/packages/*.md"),
      "Creating plugins": Path.wildcard("guides/membrane_tutorials/create_new_plugin/*.md"),
      Broadcasting: Path.wildcard("guides/membrane_tutorials/broadcasting/*.md"),
      Glossary: Path.wildcard("guides/membrane_tutorials/glossary/*.md"),
      H264: Path.wildcard("guides/membrane_tutorials/h264/*.md"),
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
      {:ex_doc, "~> 0.39", only: :dev, runtime: false},
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
