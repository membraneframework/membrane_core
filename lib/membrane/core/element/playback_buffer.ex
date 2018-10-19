defmodule Membrane.Core.Element.PlaybackBuffer do
  @moduledoc false
  # Buffer for storing messages that cannot be handled in current playback state.
  # Allows to avoid race conditions when one element changes playback state
  # before another does.

  alias Membrane.{Buffer, Core, Event}
  alias Core.Playback

  alias Core.Element.{
    BufferController,
    CapsController,
    DemandController,
    EventController,
    PadModel,
    State
  }

  require PadModel
  use Core.Element.Log
  use Bunch
  use Bunch.Access

  @type t :: %__MODULE__{
          q: Qex.t()
        }

  @type message_t :: {:demand | :buffer | :caps | :event, args :: list}

  defstruct q: nil

  @qe Qex

  @spec new() :: t
  def new do
    %__MODULE__{q: @qe.new}
  end

  @doc """
  Stores message if it cannot be handled yet.
  """
  @spec store(message_t, State.t()) :: State.stateful_try_t()
  def store(msg, %State{playback: %Playback{state: :playing}} = state), do: exec(msg, state)

  def store({type, _args} = msg, state)
      when type in [:event, :caps] do
    exec(msg, state)
    |> provided(
      that: state.playback_buffer |> empty?,
      else:
        state
        |> Bunch.Access.update_in([:playback_buffer, :q], fn q -> q |> @qe.push(msg) end)
        ~> (state -> {:ok, state})
    )
  end

  def store(msg, state) do
    state
    |> Bunch.Access.update_in([:playback_buffer, :q], fn q -> q |> @qe.push(msg) end)
    ~> (state -> {:ok, state})
  end

  @doc """
  Handles messages from buffer and passes them to proper controller, until they
  can be handled in current playback state.
  """
  @spec eval(State.t()) :: State.stateful_try_t()
  def eval(%State{playback: %Playback{state: :playing}} = state) do
    debug("evaluating playback buffer", state)

    with {:ok, state} <-
           state.playback_buffer.q
           |> Bunch.Enum.try_reduce(state, &exec/2),
         do: {:ok, state |> Bunch.Access.put_in([:playback_buffer, :q], @qe.new)}
  end

  def eval(state), do: {:ok, state}

  @spec empty?(t) :: boolean
  defp empty?(%__MODULE__{q: q}), do: q |> Enum.empty?()

  @spec exec(message_t, State.t()) :: State.stateful_try_t()
  # Callback invoked on demand request coming from the output pad in the pull mode
  defp exec({:demand, [size, pad_ref]}, state) do
    PadModel.assert_data!(pad_ref, %{direction: :output}, state)

    demand =
      if size == 0 do
        "dumb demand"
      else
        "demand of size #{inspect(size)}"
      end

    debug("Received #{demand} on pad #{inspect(pad_ref)}", state)
    DemandController.handle_demand(pad_ref, size, state)
  end

  # Callback invoked on buffer coming through the input pad
  defp exec({:buffer, [buffers, pad_ref]}, state) do
    PadModel.assert_data!(pad_ref, %{direction: :input}, state)

    debug(
      ["
      Received buffers on pad #{inspect(pad_ref)}
      Buffers: ", Buffer.print(buffers)],
      state
    )

    {messages, state} = PadModel.get_and_update_data!(pad_ref, :sticky_messages, &{&1, []}, state)

    with {:ok, state} <-
           messages
           |> Enum.reverse()
           |> Bunch.Enum.try_reduce(state, fn msg, st -> msg.(st) end) do
      {:ok, state} =
        cond do
          PadModel.get_data!(pad_ref, :start_of_stream?, state) |> Kernel.not() ->
            EventController.handle_event(pad_ref, %Event.StartOfStream{}, state)

          true ->
            {:ok, state}
        end

      BufferController.handle_buffer(pad_ref, buffers, state)
    end
  end

  # Callback invoked on incoming caps
  defp exec({:caps, [caps, pad_ref]}, state) do
    PadModel.assert_data!(pad_ref, %{direction: :input}, state)

    debug(
      """
      Received caps on pad #{inspect(pad_ref)}
      Caps: #{inspect(caps)}
      """,
      state
    )

    CapsController.handle_caps(pad_ref, caps, state)
  end

  # Callback invoked on incoming event
  defp exec({:event, [event, pad_ref]}, state) do
    PadModel.assert_instance!(pad_ref, state)

    debug(
      """
      Received event on pad #{inspect(pad_ref)}
      Event: #{inspect(event)}
      """,
      state
    )

    do_exec = fn state ->
      EventController.handle_event(pad_ref, event, state)
    end

    if event |> Event.sticky?() do
      PadModel.update_data!(
        pad_ref,
        :sticky_messages,
        &[do_exec | &1],
        state
      )
      ~> {:ok, &1}
    else
      do_exec.(state)
    end
  end
end
