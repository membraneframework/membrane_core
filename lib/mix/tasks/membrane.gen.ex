defmodule Mix.Tasks.Membrane.Gen do
  @shortdoc "Lists all available Membrane component generators"
  @moduledoc @shortdoc
  use Mix.Task

  @impl true
  def run(_argv) do
    Mix.Tasks.Help.run(["--search", "membrane.gen."])
  end
end
