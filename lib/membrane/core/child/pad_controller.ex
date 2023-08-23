defmodule Membrane.Core.Child.PadController do
  @moduledoc false

  alias Membrane.Core.Child.{PadModel, PadSpecHandler}
  alias Membrane.{LinkError, Pad}

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
