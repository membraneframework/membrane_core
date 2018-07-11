defmodule Membrane.Core.Element.PadSpecHandler do
  alias Membrane.Element.Pad
  alias Membrane.Core
  alias Core.Element.State
  require Pad
  use Membrane.Helper
  use Core.Element.Log

  def init_pads(%State{module: module} = state) do
    with {:ok, parsed_src_pads} <- handle_known_pads(:known_source_pads, :source, module),
         {:ok, parsed_sink_pads} <- handle_known_pads(:known_sink_pads, :sink, module) do
      pads = %{
        data: %{},
        info: Map.merge(parsed_src_pads, parsed_sink_pads),
        dynamic_currently_linking: []
      }

      {:ok, %State{state | pads: pads}}
    else
      {:error, reason} -> warn_error("Error parsing pads", reason, state)
    end
  end

  defp handle_known_pads(known_pads_fun, direction, module) do
    known_pads =
      if function_exported?(module, known_pads_fun, 0) do
        apply(module, known_pads_fun, [])
      else
        %{}
      end

    with {:ok, pads} <- known_pads |> Helper.Enum.map_with(&parse_pad(&1, direction)) do
      pads =
        pads
        |> Enum.map(&init_pad_info/1)
        |> Map.new(&{&1.name, &1})

      {:ok, pads}
    end
  end

  defp parse_pad({name, {availability, :push, caps}}, direction)
       when is_atom(name) and Pad.is_availability(availability) do
    {:ok, {name, availability, :push, caps, direction, %{}}}
  end

  defp parse_pad({name, {availability, :pull, caps}}, :source)
       when is_atom(name) and Pad.is_availability(availability) do
    {:ok, {name, availability, :pull, caps, :source, %{other_demand_in: nil}}}
  end

  defp parse_pad({name, {availability, {:pull, demand_in: demand_in}, caps}}, :sink)
       when is_atom(name) and Pad.is_availability(availability) do
    {:ok, {name, availability, :pull, caps, :sink, %{demand_in: demand_in}}}
  end

  defp parse_pad(params, direction),
    do: {:error, {:invalid_pad_config, params, direction: direction}}

  defp init_pad_info({name, availability, mode, caps, direction, options}) do
    %{
      name: name,
      mode: mode,
      direction: direction,
      accepted_caps: caps,
      availability: availability,
      options: options
    }
    |> Map.merge(
      case availability |> Pad.availability_mode() do
        :dynamic -> %{current_id: 0}
        :static -> %{}
      end
    )
  end
end
