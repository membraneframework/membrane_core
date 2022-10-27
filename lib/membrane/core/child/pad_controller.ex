defmodule Membrane.Core.Child.PadController do
  @moduledoc false

  alias Membrane.Core.Child.{PadModel, PadSpecHandler}
  alias Membrane.{LinkError, Pad}

  require Membrane.Core.Child.PadModel
  require Membrane.Logger

  @type state_t :: Membrane.Core.Bin.State.t() | Membrane.Core.Element.State.t()

  @spec validate_pad_being_linked!(
          Pad.direction_t(),
          PadModel.pad_info_t()
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
          {Pad.ref_t(), info :: PadModel.pad_info_t() | PadModel.pad_data_t()},
          {Pad.ref_t(), other_info :: PadModel.pad_info_t() | PadModel.pad_data_t()}
        ) :: :ok
  def validate_pad_mode!(this, that) do
    :ok = do_validate_pad_mode!(this, that)
    :ok = do_validate_pad_mode!(that, this)
    :ok
  end

  defp do_validate_pad_mode!(
         {from, %{direction: :output, mode: :pull}},
         {to, %{direction: :input, mode: :push}}
       ) do
    raise LinkError,
          "Cannot connect pull output #{inspect(from)} to push input #{inspect(to)}"
  end

  defp do_validate_pad_mode!(_pad, _other_pad) do
    :ok
  end

  @spec parse_pad_options!(Pad.name_t(), Membrane.ChildrenSpec.pad_options_t(), state_t()) ::
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

  @spec assert_all_static_pads_linked!(state_t) :: :ok
  def assert_all_static_pads_linked!(state) do
    linked_pads_names = state.pads_data |> Map.values() |> MapSet.new(& &1.name)

    static_unlinked_pads =
      state.pads_info
      |> Map.values()
      |> Enum.filter(
        &(Pad.availability_mode(&1.availability) == :static and &1.name not in linked_pads_names)
      )

    unless Enum.empty?(static_unlinked_pads) do
      raise LinkError, """
      Some static pads remained unlinked: #{inspect(Enum.map(static_unlinked_pads, & &1.name))}
      State: #{inspect(state, pretty: true)}
      """
    end

    :ok
  end
end
