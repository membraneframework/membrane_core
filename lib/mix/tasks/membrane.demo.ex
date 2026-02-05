defmodule Mix.Tasks.Membrane.Demo do
  @shortdoc "Generate Membrane demos and examples"
  @moduledoc """
  Generate Membrane demos and examples

    $ mix membrane.demo [-a] [-l] demos ...


  """

  @demos_readme_url "https://raw.githubusercontent.com/membraneframework/membrane_demo/refs/heads/master/README.md"
  use Mix.Task

  @impl true
  def run([]) do
    Mix.Tasks.Help.run(["membrane.demo"])
  end

  def run(argv) do
    {:ok, _} = Application.ensure_all_started(:req)
    response = Req.get!(@demos_readme_url)

    demos_info =
      response.body
      |> String.split("\n")
      |> Enum.map(&Regex.named_captures(~r/^- \[(?<name>.*?)\]\(.*?\) - (?<description>.*)/, &1))
      |> Enum.filter(&(&1 != nil))
      |> Enum.map(
        &Map.update!(
          &1,
          "description",
          fn description -> Regex.replace(~r/\[(.*?)\]\(.*?\)/, description, "\\1") end
        )
      )

    max_name_length =
      demos_info
      |> Enum.map(&String.length(&1["name"]))
      |> Enum.max()

    demos_info
    |> Enum.each(fn %{"name" => name, "description" => description} ->
      dots_line = String.duplicate(".", max_name_length - String.length(name) + 3)
      Mix.shell().info(" | #{name} #{dots_line} | #{description}")
    end)

    # |> Enum.each(&Mix.shell().info("#{&1["package"]} - #{&1["description"]}"))
  end
end
