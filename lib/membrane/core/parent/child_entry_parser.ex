defmodule Membrane.Core.Parent.ChildEntryParser do
  @moduledoc false

  alias Membrane.{ChildEntry, ChildrenSpec, ParentError}

  @type raw_child_entry :: %ChildEntry{
          name: Membrane.Child.name(),
          module: module,
          options: struct | nil,
          component_type: :element | :bin
        }

  @spec parse([ChildrenSpec.Builder.child_spec()]) ::
          [raw_child_entry] | no_return
  def parse(children_spec) do
    Enum.map(children_spec, &parse_child/1)
  end

  defp parse_child({name, %module{} = struct, _options}) do
    %ChildEntry{
      name: name,
      module: module,
      options: struct,
      component_type: component_type(module)
    }
  end

  defp parse_child({name, module, _options}) when is_atom(module) do
    struct = module |> Bunch.Module.struct()

    %ChildEntry{
      name: name,
      module: module,
      options: struct,
      component_type: component_type(module)
    }
  end

  defp parse_child(config) do
    raise ParentError, "Invalid children config: #{inspect(config, pretty: true)}"
  end

  defp component_type(module) do
    cond do
      Membrane.Element.element?(module) -> :element
      Membrane.Bin.bin?(module) -> :bin
      true -> raise ParentError, not_child: module
    end
  end
end
