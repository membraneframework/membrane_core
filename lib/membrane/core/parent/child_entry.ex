defmodule Membrane.Core.Parent.ChildEntry do
  @moduledoc false

  alias Membrane.{ParentError, ParentSpec}

  @type unresolved_t :: %Membrane.ChildEntry{
          name: Membrane.Child.name_t(),
          module: module,
          options: struct | nil,
          component_type: :element | :bin,
          pid: pid | nil,
          clock: Membrane.Clock.t() | nil,
          sync: Membrane.Sync.t() | nil,
          pending?: boolean()
        }

  @spec from_spec(ParentSpec.children_spec_t() | any) :: [Membrane.ChildEntry.t()] | no_return
  def from_spec(children_spec) when is_map(children_spec) or is_list(children_spec) do
    children_spec |> Enum.map(&parse_child/1)
  end

  defp parse_child({name, %module{} = options}) do
    %Membrane.ChildEntry{
      name: name,
      module: module,
      options: options,
      component_type: component_type(module),
      pending?: false
    }
  end

  defp parse_child({name, module}) when is_atom(module) do
    options = module |> Bunch.Module.struct()

    %Membrane.ChildEntry{
      name: name,
      module: module,
      options: options,
      component_type: component_type(module),
      pending?: false
    }
  end

  defp parse_child(config) do
    raise ParentError, "Invalid children config: #{inspect(config, pretty: true)}"
  end

  defp component_type(module) do
    cond do
      Membrane.Element.element?(module) ->
        :element

      Membrane.Bin.bin?(module) ->
        :bin

      true ->
        raise ParentError, """
        Child module #{inspect(module)} is neither Membrane Element nor Bin.
        Make sure that given module is the right one, implements proper behaviour
        and all needed dependencies are properly specified in the Mixfile.
        """
    end
  end
end
