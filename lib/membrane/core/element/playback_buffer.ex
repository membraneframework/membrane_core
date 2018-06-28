defmodule Membrane.Core.Element.PlaybackBuffer do
  alias Membrane.Core.Playback
  alias Membrane.{Buffer, Core, Event}
  alias Core.Element.{Common, PadsController, State}
  use Core.Element.Log
  use Membrane.Helper

  @type t :: %__MODULE__{
          q: Qex.t()
        }

  defstruct q: nil

  @qe Qex

  def new do
    %__MODULE__{q: @qe.new}
  end

  def store(msg, %State{playback: %Playback{state: :playing}} = state), do: exec(msg, state)

  def store({type, _args} = msg, state)
      when type in [:membrane_event, :membrane_caps] do
    exec(msg, state)
    |> provided(
      that: state.playback_buffer |> empty?,
      else:
        state
        |> Helper.Struct.update_in([:playback_buffer, :q], fn q -> q |> @qe.push(msg) end)
        ~> (state -> {:ok, state})
    )
  end

  def store(msg, state) do
    state
    |> Helper.Struct.update_in([:playback_buffer, :q], fn q -> q |> @qe.push(msg) end)
    ~> (state -> {:ok, state})
  end

  def eval(%State{playback: %Playback{state: :playing}} = state) do
    debug("evaluating playback buffer", state)

    with {:ok, state} <-
           state.playback_buffer.q
           |> Helper.Enum.reduce_with(state, &exec/2),
         do: {:ok, state |> Helper.Struct.put_in([:playback_buffer, :q], @qe.new)}
  end

  def eval(state), do: {:ok, state}

  def empty?(%__MODULE__{q: q}), do: q |> Enum.empty?()

  # Callback invoked on demand request coming from the source pad in the pull mode
  defp exec({:membrane_demand, [size, pad_name]}, state) do
    {:ok, _} = state |> PadsController.get_pad_data(:source, pad_name)

    demand =
      if size == 0 do
        "dumb demand"
      else
        "demand of size #{inspect(size)}"
      end

    debug("Received #{demand} on pad #{inspect(pad_name)}", state)
    Common.handle_demand(pad_name, size, state)
  end

  # Callback invoked on buffer coming through the sink pad
  defp exec({:membrane_buffer, [buffers, pad_name]}, state) do
    {:ok, %{mode: mode}} = state |> PadsController.get_pad_data(:sink, pad_name)

    debug(
      ["
      Received buffers on pad #{inspect(pad_name)}
      Buffers: ", Buffer.print(buffers)],
      state
    )

    {{:ok, messages}, state} =
      state
      |> PadsController.get_update_pad_data(
        :sink,
        pad_name,
        :sticky_messages,
        &{{:ok, &1 |> Enum.reverse()}, []}
      )

    with {:ok, state} <-
           messages
           |> Helper.Enum.reduce_with(state, fn msg, st -> msg.(st) end) do
      {:ok, state} =
        cond do
          state |> PadsController.get_pad_data!(:sink, pad_name, :sos) |> Kernel.not() ->
            event = %{Event.sos() | payload: :auto_sos}
            Common.handle_event(pad_name, event, state)

          true ->
            {:ok, state}
        end

      Common.handle_buffer(mode, pad_name, buffers, state)
    end
  end

  # Callback invoked on incoming caps
  defp exec({:membrane_caps, [caps, pad_name]}, state) do
    {:ok, %{mode: mode}} = state |> PadsController.get_pad_data(:sink, pad_name)

    debug(
      """
      Received caps on pad #{inspect(pad_name)}
      Caps: #{inspect(caps)}
      """,
      state
    )

    Common.handle_caps(mode, pad_name, caps, state)
  end

  # Callback invoked on incoming event
  defp exec({:membrane_event, [event, pad_name]}, state) do
    exec = fn state ->
      {:ok, _data} = state |> PadsController.get_pad_data(:any, pad_name)

      debug(
        """
        Received event on pad #{inspect(pad_name)}
        Event: #{inspect(event)}
        """,
        state
      )

      Common.handle_event(pad_name, event, state)
    end

    case event.stick_to do
      :nothing ->
        exec.(state)

      :buffer ->
        state
        |> PadsController.update_pad_data(:sink, pad_name, :sticky_messages, &{:ok, [exec | &1]})
    end
  end
end
