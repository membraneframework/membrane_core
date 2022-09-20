defmodule Membrane.Core.Parent.ChildEntryParser do
  @moduledoc false

  alias Membrane.{ChildEntry, ParentError, ParentSpec}

  @type raw_child_entry_t :: %ChildEntry{
          name: Membrane.Child.name_t(),
          module: module,
          options: struct | nil,
          component_type: :element | :bin
        }

  @spec parse({Membrane.Child.name_t(), ParentSpec.child_spec_t()} | any) ::
          [raw_child_entry_t] | no_return
  def parse(children_spec)
      when is_map(children_spec) or is_list(children_spec) do
    children_spec |> Enum.map(&parse_child/1)
  end

  defp parse_child({name, %module{} = options}) do
    %ChildEntry{
      name: name,
      module: module,
      options: options,
      component_type: component_type(module)
    }
  end

  defp parse_child({name, module}) when is_atom(module) do
    options = module |> Bunch.Module.struct()

    %ChildEntry{
      name: name,
      module: module,
      options: options,
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
