defmodule Membrane.Core.Child.PadController do
  alias Membrane.Core.InputBuffer
  alias Membrane.Core.Child.{PadModel, PadSpecHandler}
  alias Membrane.LinkError
  alias Membrane.Pad

  require Membrane.Core.Child.PadModel
  require Membrane.Logger

  @type parsed_pad_props_t :: %{buffer: InputBuffer.props_t(), options: map}

  @type state_t :: Membrane.Core.Bin.State.t() | Membrane.Core.Element.State.t()

  @spec validate_pad_being_linked!(
          Pad.ref_t(),
          Pad.direction_t(),
          PadModel.pad_info_t(),
          state_t()
        ) :: :ok
  def validate_pad_being_linked!(pad_ref, direction, info, state) do
    cond do
      :ok == PadModel.assert_data(state, pad_ref, linked?: true) ->
        raise LinkError, "Pad #{inspect(pad_ref)} has already been linked"

      info.direction != direction ->
        raise LinkError, """
        Invalid pad direction:
          expected: #{inspect(info.direction)},
          actual: #{inspect(direction)}
        """

      true ->
        :ok
    end
  end

  @spec validate_pad_mode!(
          {Pad.ref_t(), info :: PadModel.pad_info_t()},
          {Pad.ref_t(), other_info :: PadModel.pad_info_t()}
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

  @spec parse_pad_props!(ParentSpec.pad_props_t(), Pad.name_t(), state_t()) ::
          parsed_pad_props_t | no_return
  def parse_pad_props!(props, pad_name, state) do
    {_, pad_spec} = PadSpecHandler.get_pads(state) |> Enum.find(fn {k, _} -> k == pad_name end)
    pad_opts = parse_pad_options!(pad_name, pad_spec.options, props[:options])
    buffer_props = parse_buffer_props!(pad_name, props[:buffer])
    %{options: pad_opts, buffer: buffer_props}
  end

  defp parse_pad_options!(_pad_name, nil, nil) do
    nil
  end

  defp parse_pad_options!(pad_name, nil, options) do
    raise LinkError,
          "Pad #{inspect(pad_name)} does not define any options, got #{inspect(options)}"
  end

  defp parse_pad_options!(pad_name, options_spec, options) do
    bunch_field_specs = options_spec |> Bunch.KVList.map_values(&Keyword.take(&1, [:default]))

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

  defp parse_buffer_props!(pad_name, props) do
    case InputBuffer.parse_props(props) do
      {:ok, buffer_props} ->
        buffer_props

      {:error, {:config_invalid_keys, keys}} ->
        raise LinkError,
              "Invalid keys in buffer options of pad #{inspect(pad_name)}: #{inspect(keys)}"
    end
  end

  def check_for_unlinked_static_pads(state) do
    linked_pads_names = state.pads.data |> Map.values() |> Enum.map(& &1.name) |> MapSet.new()

    static_unlinked_pads =
      state.pads.info
      |> Map.values()
      |> Enum.filter(
        &(Pad.availability_mode(&1.availability) == :static and &1.name not in linked_pads_names)
      )

    unless Enum.empty?(static_unlinked_pads) do
      Membrane.Logger.warn("""
      Some static pads remained unlinked: #{inspect(Enum.map(static_unlinked_pads, & &1.name))}
      State: #{inspect(state, pretty: true)}
      """)
    end

    :ok
  end
end
