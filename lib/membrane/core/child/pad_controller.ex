defmodule Membrane.Core.Child.PadController do
  @moduledoc false

  alias Membrane.Core.Child.{PadModel, PadSpecHandler}
  alias Membrane.{LinkError, Pad}

  require Membrane.Core.Child.PadModel

  @type state :: Membrane.Core.Bin.State.t() | Membrane.Core.Element.State.t()

  @spec validate_pad_being_linked!(
          Pad.direction(),
          PadModel.pad_info()
        ) :: :ok
  def validate_pad_being_linked!(direction, info) do
    if info.direction != direction do
      raise LinkError, """
      Invalid pad direction:
        expected: #{inspect(info.direction)},
        actual: #{inspect(direction)}
      """
    end

    :ok
  end

  @spec validate_pad_mode!(
          {Pad.ref(), info :: PadModel.pad_info() | PadModel.pad_data()},
          {Pad.ref(), other_info :: PadModel.pad_info() | PadModel.pad_data()}
        ) :: :ok
  def validate_pad_mode!(this, that) do
    :ok = do_validate_pad_mode!(this, that)
    :ok = do_validate_pad_mode!(that, this)
    :ok
  end

  defp do_validate_pad_mode!(
         {from, %{direction: :output, flow_control: from_flow_control}},
         {to, %{direction: :input, flow_control: :push}}
       )
       when from_flow_control in [:auto, :manual] do
    raise LinkError,
          "Cannot connect #{inspect(from_flow_control)} output #{inspect(from)} to push input #{inspect(to)}"
  end

  defp do_validate_pad_mode!(_pad, _other_pad) do
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
