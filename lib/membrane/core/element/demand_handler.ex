defmodule Membrane.Core.Element.DemandHandler do
  @moduledoc false

  # Module handling demands requested on output pads.

  use Bunch

  alias Membrane.Core.InputBuffer
  alias Membrane.Core.Child.PadModel

  alias Membrane.Core.Element.{
    BufferController,
    CapsController,
    DemandController,
    EventController,
    State
  }

  alias Membrane.Pad

  require Membrane.Core.Child.PadModel
  require Membrane.Core.Message
  require Membrane.Logger

  @doc """
  Updates demand on the given input pad that should be supplied by future calls
  to `supply_demand/2` or `check_and_supply_demands/2`.
  """
  @spec update_demand(
          Pad.ref_t(),
          pos_integer,
          State.t()
        ) :: State.stateful_try_t()
  def update_demand(pad_ref, size, state) when is_integer(size) do
    state = PadModel.set_data!(state, pad_ref, :demand, size)
    {:ok, state}
  end

  def update_demand(pad_ref, size_fun, state) when is_function(size_fun) do
    PadModel.update_data(
      state,
      pad_ref,
      :demand,
      fn demand ->
        new_demand = size_fun.(demand)

        if new_demand < 0 do
          {:error, :negative_demand}
        else
          {:ok, new_demand}
        end
      end
    )
  end

  @doc """
  Delays executing redemand until all current processing is finished.

  Works similar to `delay_supply/3`, but only `:sync` mode is supported. See
  doc for `delay_supply/3` for more info.
  """
  @spec delay_redemand(Pad.ref_t(), State.t()) :: State.t()
  def delay_redemand(pad_ref, state) do
    state
    |> Map.update!(:delayed_demands, &MapSet.put(&1, {pad_ref, :redemand}))
  end

  @spec handle_delayed_demands(State.t()) :: State.stateful_try_t()
  def handle_delayed_demands(%State{delayed_demands: del_dem} = state)
      when del_dem == %MapSet{} do
    {:ok, state}
  end

  def handle_delayed_demands(%State{delayed_demands: del_dem} = state) do
    # Taking random element of `:delayed_demands` is done to keep data flow
    # balanced among pads, i.e. to prevent situation where demands requested by
    # one pad are supplied right away while another one is waiting for buffers
    # potentially for a long time.
    [{pad_ref, action}] = del_dem |> Enum.take_random(1)
    state = %State{state | delayed_demands: del_dem |> MapSet.delete({pad_ref, action})}

    case action do
      :supply ->
        supply_demand(pad_ref, state)

      :redemand ->
        handle_redemand(pad_ref, state)
    end
  end

  @doc """
  Called when redemand action was returned.
    * If element is currently supplying demand it means that after finishing supply_demand it will call
      `handle_delayed_demands`.
    * If element isn't supplying demand at the moment `handle_demand` is invoked right away, and it will
      invoke handle_demand callback, which will probably return :redemand and :buffers and in that way
      source will synchronously supply demand.
  """
  @spec handle_redemand(Pad.ref_t(), State.t()) :: {:ok, State.t()}
  def handle_redemand(pad_ref, %State{supplying_demand?: true} = state) do
    state =
      state
      |> Map.update!(:delayed_demands, &MapSet.put(&1, {pad_ref, :redemand}))

    {:ok, state}
  end

  def handle_redemand(pad_ref, state) do
    DemandController.handle_demand(pad_ref, 0, state)
  end

  @doc """
  If element is not supplying demand currently, this function supplies
  demand right away by taking buffers from the InputBuffer of the given pad
  and passing it to proper controllers.

  If element is currently supplying demand it delays supplying demand until all
  current processing is finished.

  This is necessary due to the case when one requests a demand action while previous
  demand is being supplied. This could lead to a situation where buffers are taken
  from InputBuffer and passed to callbacks, while buffers being currently supplied
  have not been processed yet, and therefore to changing order of buffers.
  """
  @spec supply_demand(
          Pad.ref_t(),
          State.t()
        ) :: State.stateful_try_t()
  def supply_demand(pad_ref, %State{supplying_demand?: true} = state) do
    state =
      state
      |> Map.update!(:delayed_demands, &MapSet.put(&1, {pad_ref, :supply}))

    {:ok, state}
  end

  def supply_demand(pad_ref, state) do
    with {:ok, state} <- do_supply_demand(pad_ref, %State{state | supplying_demand?: true}) do
      handle_delayed_demands(%State{state | supplying_demand?: false})
    end
  end

  defp do_supply_demand(pad_ref, state) do
    pad_data = state |> PadModel.get_data!(pad_ref)

    {{_buffer_status, data}, new_input_buf} =
      InputBuffer.take_and_demand(
        pad_data.input_buf,
        pad_data.demand,
        pad_data.pid,
        pad_data.other_ref
      )

    state = PadModel.set_data!(state, pad_ref, :input_buf, new_input_buf)

    with {:ok, state} <- handle_input_buf_output(pad_ref, data, state) do
      {:ok, state}
    else
      {{:error, reason}, state} ->
        Membrane.Logger.error("""
        Error while supplying demand on pad #{inspect(pad_ref)} of size #{
          inspect(pad_data.demand)
        }
        """)

        {{:error, {:supply_demand, reason}}, state}
    end
  end

  @spec handle_input_buf_output(
          Pad.ref_t(),
          [InputBuffer.output_value_t()],
          State.t()
        ) :: State.stateful_try_t()
  defp handle_input_buf_output(pad_ref, data, state) do
    data
    |> Bunch.Enum.try_reduce(state, fn v, state ->
      do_handle_input_buf_output(pad_ref, v, state)
    end)
  end

  @spec do_handle_input_buf_output(
          Pad.ref_t(),
          InputBuffer.output_value_t(),
          State.t()
        ) :: State.stateful_try_t()
  defp do_handle_input_buf_output(pad_ref, {:event, e}, state),
    do: EventController.exec_handle_event(pad_ref, e, state)

  defp do_handle_input_buf_output(pad_ref, {:caps, c}, state),
    do: CapsController.exec_handle_caps(pad_ref, c, state)

  defp do_handle_input_buf_output(
         pad_ref,
         {:buffers, buffers, size},
         state
       ) do
    state = PadModel.update_data!(state, pad_ref, :demand, &(&1 - size))

    BufferController.exec_buffer_handler(pad_ref, buffers, state)
  end
end
