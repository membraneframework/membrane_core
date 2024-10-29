defmodule Membrane.Core.Child.PadController do
  @moduledoc false

  alias Membrane.Core.Child.{PadModel, PadSpecHandler}
  alias Membrane.{LinkError, Pad, PadError}

  require Membrane.Core.Child.PadModel

  @type state :: Membrane.Core.Bin.State.t() | Membrane.Core.Element.State.t()

  @spec validate_pad_direction!(
          Pad.direction(),
          PadModel.pad_info()
        ) :: :ok
  def validate_pad_direction!(direction, %{direction: direction}), do: :ok

  def validate_pad_direction!(direction, pad_info) do
    raise LinkError, """
    Invalid pad direction:
      expected: #{inspect(pad_info.direction)},
      actual: #{inspect(direction)}
    """
  end

  @spec validate_pads_flow_control_compability!(
          Pad.ref(),
          Pad.flow_control(),
          Pad.ref(),
          Pad.flow_control()
        ) :: :ok
  def validate_pads_flow_control_compability!(from, from_flow_control, to, to_flow_control) do
    if from_flow_control in [:auto, :manual] and to_flow_control == :push do
      raise LinkError,
            "Cannot connect #{inspect(from_flow_control)} output #{inspect(from)} to push input #{inspect(to)}"
    end

    :ok
  end

  @spec validate_pad_instances!(Pad.name(), state()) :: :ok
  def validate_pad_instances!(pad_name, state) do
    with %{max_instances: max_instances} when is_integer(max_instances) <-
           state.pads_info[pad_name] do
      current_number =
        state.pads_data
        |> Enum.count(fn {_ref, data} -> data.name == pad_name end)

      if max_instances <= current_number do
        raise PadError, """
        Only #{max_instances} instances of pad #{inspect(pad_name)} can exist within this component, \
        while  an attempt to create #{current_number + 1} instances was made. Set `:max_instances` option \
        to a different value, to change this boundary.
        """
      end
    end

    :ok
  end

  @spec parse_pad_options!(Pad.name(), Membrane.ChildrenSpec.pad_options(), state()) ::
          map | no_return
  def parse_pad_options!(pad_name, options, state) do
    {_pad_name, pad_spec} =
      PadSpecHandler.get_pads(state) |> Enum.find(fn {k, _} -> k == pad_name end)

    bunch_field_specs =
      Bunch.KVList.map_values(pad_spec.options || [], &Keyword.take(&1, [:default]))

    case options |> List.wrap() |> Bunch.Config.parse(bunch_field_specs) do
      {:ok, options} ->
        options

      {:error, {:config_field, {:key_not_found, key}}} ->
        raise LinkError, "Missing option #{inspect(key)} for pad #{inspect(pad_name)}"

      {:error, {:config_invalid_keys, keys}} ->
        raise LinkError,
              "Invalid keys in options of pad #{inspect(pad_name)} - #{inspect(keys)}"
    end
  end
end
