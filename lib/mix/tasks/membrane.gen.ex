[Filter, Endpoint, Sink, Source, Bin, Pipeline]
|> Enum.map(fn component_type ->
  defmodule Module.concat(Mix.Tasks.Membrane.Gen, component_type) do
    @moduledoc """
    Generates a template for a #{inspect(component_type)} with the provided module name.

        $ mix membrane.gen.#{component_type |> Atom.to_string() |> String.downcase()} module_name [-l target_location]

    ## Options
    ### `-l, --location`
    If a target location is provided, the #{inspect(component_type)} will be created there, relative to the `lib` directory.
    The filename must also be present and most likely have an `.ex` extension. If location is not provided, then it will be
    inferred from the provided module name - it will be converted to lowercase and `.` separators will be interpreted
    as directory separators. For example, a #{inspect(component_type)} with module name `Foo.Bar` will be created at `lib/foo/bar.ex`. 
    """
    use Mix.Task

    @switches [location: :string]
    @aliases [l: :location]

    @impl true
    def run(argv) do
      {path_option, argv} = OptionParser.parse!(argv, aliases: @aliases, strict: @switches)

      module =
        case argv do
          [] -> raise "Module name not provided"
          [module_name | _rest] -> Module.concat([module_name])
        end

      component_path =
        case path_option do
          [] -> infer_path_from_module(module)
          [{:location, path} | _rest] -> path
        end
        |> then(&Path.join("lib", &1))

      File.mkdir_p!(Path.dirname(component_path))

      File.write!(component_path, get_component(unquote(component_type), module))
    end

    defp infer_path_from_module(module) do
      module
      |> inspect()
      |> String.downcase()
      |> String.split(".")
      |> List.update_at(-1, &"#{&1}.ex")
      |> Path.join()
    end

    defp get_component(type, module) do
      template =
        "../../../templates"
        |> Path.expand(__DIR__)
        |> Path.join(String.downcase(inspect(type)) <> ".ex")
        |> File.read!()

      template
      |> String.split("\n")
      |> List.replace_at(0, "defmodule #{inspect(module)} do")
      |> Enum.join("\n")
    end
  end
end)
