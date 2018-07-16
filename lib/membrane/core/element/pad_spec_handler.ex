defmodule Membrane.Core.Element.PadSpecHandler do
  @moduledoc false
  # Module parsing pads specifications in elements.

  alias Membrane.Element
  alias Element.Pad
  alias Membrane.{Caps, Core}
  alias Core.Element.{PadModel, State}
  require Pad
  use Membrane.Helper
  use Core.Element.Log

  @typep parsed_pad_t ::
           {Pad.class_name_t(), Pad.availability_t(), Pad.mode_t(), Caps.Matcher.caps_specs_t(),
            Pad.direction_t(), map}

  @doc """
  Initializes pads info basing on element's pads specifications.
  """
  @spec init_pads(State.t()) :: State.stateful_try_t()
  def init_pads(%State{module: module} = state) do
    with {:ok, soruce_pads_info} <- handle_known_pads(:known_source_pads, :source, module),
         {:ok, sink_pads_info} <- handle_known_pads(:known_sink_pads, :sink, module) do
      pads = %{
        data: %{},
        info: Map.merge(soruce_pads_info, sink_pads_info),
        dynamic_currently_linking: []
      }

      {:ok, %State{state | pads: pads}}
    else
      {:error, reason} -> warn_error("Error parsing pads", reason, state)
    end
  end

  @spec handle_known_pads(atom, Pad.direction_t(), module) ::
          {:ok, %{Pad.name_t() => PadModel.pad_info_t()}}
          | {:error, {:invalid_pad_config, details :: Keyword.t()}}
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
        |> Map.new(&{&1.class_name, &1})

      {:ok, pads}
    end
  end

  @spec parse_pad(Element.pad_specs_t(), Pad.direction_t()) ::
          {:ok, parsed_pad_t} | {:error, {:invalid_pad_config, details :: Keyword.t()}}
  defp parse_pad({class_name, {availability, :push, caps}}, direction)
       when Pad.is_class_name(class_name) and Pad.is_availability(availability) do
    {:ok, {class_name, availability, :push, caps, direction, %{}}}
  end

  defp parse_pad({class_name, {availability, :pull, caps}}, :source)
       when Pad.is_class_name(class_name) and Pad.is_availability(availability) do
    {:ok, {class_name, availability, :pull, caps, :source, %{other_demand_in: nil}}}
  end

  defp parse_pad({class_name, {availability, {:pull, demand_in: demand_in}, caps}}, :sink)
       when Pad.is_class_name(class_name) and Pad.is_availability(availability) do
    {:ok, {class_name, availability, :pull, caps, :sink, %{demand_in: demand_in}}}
  end

  defp parse_pad(params, direction),
    do: {:error, {:invalid_pad_config, params, direction: direction}}

  @spec init_pad_info(parsed_pad_t) :: PadModel.pad_info_t()
  defp init_pad_info({class_name, availability, mode, caps, direction, options}) do
    %{
      class_name: class_name,
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
