defmodule Mix.Tasks.Membrane.Component.New do
  @moduledoc """
      $ mix membrane.component.new PATH [--source | --sink | --filter | --endpoint | --bin | --pipeline MODULE]...
  """
  use Mix.Task

  @switches [
    source: :string,
    sink: :string,
    filter: :string,
    endpoint: :string,
    bin: :string,
    pipeline: :string
  ]

  @impl true
  def run(argv) do
    {components, argv} = OptionParser.parse!(argv, strict: @switches)

    base_dir =
      case argv do
        [] -> File.cwd!()
        [path | _rest] -> Path.expand(path)
      end

    Enum.map(components, fn {type, module_name} ->
      component_path =
        module_name
        |> String.split(".")
        |> Enum.map(&String.downcase/1)
        |> List.update_at(-1, &"#{&1}.ex")
        |> Path.join()
        |> then(&Path.join(base_dir, &1))

      File.mkdir_p!(Path.dirname(component_path))
      File.write!(component_path, get_component(type, module_name))
    end)
  end

  defp get_component(type, module_name) do
    template =
      "../../../templates"
      |> Path.expand(__DIR__)
      |> Path.join(Atom.to_string(type) <> ".ex")
      |> File.read!()

    template
    |> String.split("\n")
    |> List.replace_at(0, "defmodule Membrane.#{:string.titlecase(module_name)} do")
    |> Enum.join("\n")
  end
end
