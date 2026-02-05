[Filter, Endpoint, Sink, Source, Bin, Pipeline]
|> Enum.map(fn component_type ->
  component_name = inspect(component_type)

  defmodule Module.concat(Mix.Tasks.Membrane.Gen, component_type) do
    @shortdoc "Generates a template for a Membrane #{component_name}"
    @moduledoc """
    Generates a template for a Membrane #{component_name} with the provided module name.

      $ mix membrane.gen.#{String.downcase(component_name)} module_name [-l target_location]

    ## Options
    * `-l, --location` - If a target location is provided, the #{component_name} will be created there, relative to the `lib` directory.
      The filename must also be present and most likely have an `.ex` extension. If location is not provided, then it will be
      inferred from the provided module name - it will be converted to lowercase and `.` separators will be interpreted
      as directory separators. For example, a #{component_name} with module name `Foo.Bar` will be created at `lib/foo/bar.ex`. 
    """
    use Mix.Task

    @switches [location: :string]
    @aliases [l: :location]

    @impl true
    def run(argv) do
      do_run("lib", argv)
    end

    @doc false
    @spec do_run(binary(), [binary()]) :: any()
    def do_run(base_dir, argv) do
      {path_option, argv} = OptionParser.parse!(argv, aliases: @aliases, strict: @switches)

      module =
        case argv do
          [] ->
            Mix.raise("""
            Module name not provided.

            This task expects a module name, which the created #{unquote(component_type)} will have:

              $ mix membrane.gen.#{String.downcase(unquote(component_name))} My#{unquote(component_name)}
              
            """)

            Mix.Tasks.Help

          [module_name | _rest] ->
            Module.concat([module_name])
        end

      component_path =
        case path_option do
          [] -> infer_path_from_module(module)
          [{:location, path} | _rest] -> path
        end
        |> then(&Path.join(base_dir, &1))

      File.mkdir_p!(Path.dirname(component_path))

      File.write!(component_path, get_component(module))
    end

    defp infer_path_from_module(module) do
      module
      |> inspect()
      |> String.downcase()
      |> String.split(".")
      |> List.update_at(-1, &"#{&1}.ex")
      |> Path.join()
    end

    defp get_component(module) do
      template =
        "../../../templates"
        |> Path.expand(__DIR__)
        |> Path.join(String.downcase(inspect(unquote(component_type))) <> ".ex")
        |> File.read!()

      template
      |> String.split("\n")
      |> List.replace_at(0, "defmodule #{inspect(module)} do")
      |> Enum.join("\n")
    end
  end
end)
