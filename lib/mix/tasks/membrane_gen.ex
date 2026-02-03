[Filter, Endpoint, Sink, Source, Bin, Pipeline]
|> Enum.map(fn component_type ->
  defmodule Module.concat(Mix.Tasks.Membrane.Gen, component_type) do
    @moduledoc """
        $ mix membrane.gen.#{component_type |> Atom.to_string() |> String.downcase()} MODULE [--path PATH]
    """
    use Mix.Task

    @switches [ path: :string ]

    @impl true
    def run(argv) do
      {path_option, argv} = OptionParser.parse!(argv, strict: @switches)

      module_name =
        case argv do
          [] -> raise "Module name not provided"
          [module | _rest] -> module
        end

      component_path =
        case path_option do
          [] -> infer_path_from_module(module_name)
          [{:path, path} | _rest] -> path
        end

      File.mkdir_p!(Path.dirname(component_path))

      File.write!(component_path, get_component(unquote(component_type), module_name))
    end

    defp infer_path_from_module(module_name) do
      module_name
      |> String.split(".")
      |> Enum.map(&String.downcase/1)
      |> List.update_at(-1, &"#{&1}.ex")
      |> Path.join()
      |> then(&Path.join("lib", &1))
    end

    defp get_component(type, module_name) do
      template =
        "../../../templates"
        |> Path.expand(__DIR__)
        |> Path.join(String.downcase(inspect(type)) <> ".ex")
        |> File.read!()

      template
      |> String.split("\n")
      |> List.replace_at(0, "defmodule #{:string.titlecase(module_name)} do")
      |> Enum.join("\n")
    end
  end
end)
