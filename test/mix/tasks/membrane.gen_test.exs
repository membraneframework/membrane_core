defmodule Mix.Tasks.Membrane.GenTest do
  use ExUnit.Case
  alias Mix.Tasks.Membrane.Gen

  Enum.each([Filter, Endpoint, Sink, Source, Bin, Pipeline], fn component_type ->
    @tag :tmp_dir
    test "#{inspect(component_type)} template generates correctly", %{tmp_dir: tmp} do
      Module.concat(Gen, unquote(component_type)).do_run(tmp, [inspect(unquote(component_type))])

      {{:module, module, _contents, __result}, []} =
        Code.eval_file(Path.join(tmp, Macro.underscore(unquote(component_type)) <> ".ex"))

      attributes = module.__info__(:attributes)
      functions = module.__info__(:functions)

      if {:behaviour, [Membrane.Element.WithInputPads]} in attributes do
        assert {:handle_buffer, 4} in functions

        assert %{
                 name: :input,
                 direction: :input,
                 accepted_formats_str: ["_any"],
                 availability: :always
               } = module.membrane_pads()[:input]
      end

      if {:behaviour, [Membrane.Element.WithOutputPads]} in attributes do
        assert %{
                 name: :output,
                 direction: :output,
                 accepted_formats_str: ["_any"],
                 availability: :always
               } = module.membrane_pads()[:output]
      end

      assert Module.concat(module, State).__info__(:struct) != nil
    end
  end)
end
