defmodule Membrane.Core.Element.PlaybackBuffer do
  @moduledoc false

  # Buffer for storing messages that cannot be handled in current playback state.
  # Allows to avoid race conditions when one element changes playback state
  # before another does.

  use Bunch
  use Bunch.Access

  require Logger
  require Membrane.Core.Message
  require Membrane.Core.Child.PadModel
  require Membrane.Logger

  alias Membrane.Event
  alias Membrane.Core.Playback
  alias Membrane.Core.Child.PadModel

  alias Membrane.Core.Element.{
    BufferController,
    CapsController,
    DemandController,
    EventController,
    State
  }

  alias Membrane.Core.Message

  @type t :: %__MODULE__{
          q: Qex.t()
        }

  @type message_t :: {Message, :demand | :buffer | :caps | :event, args :: list, opts :: list}

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

  def store(
        Message.new(type, _args, _opts) = msg,
        %State{playback: %Playback{state: :prepared}} = state
      )
      when type in [:event, :caps] do
    if state.playback_buffer |> empty? do
      exec(msg, state)
    else
      do_store(msg, state)
    end
  end

  def store(msg, state) do
    do_store(msg, state)
  end

  defp do_store(msg, state) do
    state
    |> Bunch.Access.update_in([:playback_buffer, :q], &@qe.push(&1, msg))
    ~> (state -> {:ok, state})
  end

  @doc """
  Handles messages from buffer and passes them to proper controller, until they
  can be handled in current playback state.
  """
  @spec eval(State.t()) :: State.stateful_try_t()
  def eval(%State{playback: %Playback{state: :playing}} = state) do
    Logger.debug("Evaluating playback buffer")

    with {:ok, state} <-
           state.playback_buffer.q
           |> Bunch.Enum.try_reduce(state, &exec/2),
         do: {:ok, state |> Bunch.Access.put_in([:playback_buffer, :q], @qe.new)}
  end

  def eval(state), do: {:ok, state}

  def flush_for_pad(%__MODULE__{q: q} = buf, pad_ref) do
    alias Membrane.Core.Message
    require Message

    q
    |> Enum.filter(fn msg -> Message.for_pad(msg) != pad_ref end)
    |> Enum.into(%@qe{})
    ~> %{buf | q: &1}
  end

  @spec empty?(t) :: boolean
  defp empty?(%__MODULE__{q: q}), do: q |> Enum.empty?()

  @spec exec(message_t, State.t()) :: State.stateful_try_t()
  # Callback invoked on demand request coming from the output pad in the pull mode
  defp exec(Message.new(:demand, size, _opts) = msg, state) do
    pad_ref = Message.for_pad(msg)
    PadModel.assert_data!(state, pad_ref, %{direction: :output})

    Membrane.Logger.debug_verbose(
      "Received #{
        if size == 0 do
          "dumb demand"
        else
          "demand of size #{inspect(size)}"
        end
      } on pad #{inspect(pad_ref)}"
    )

    DemandController.handle_demand(pad_ref, size, state)
  end

  # Callback invoked on buffer coming through the input pad
  defp exec(Message.new(:buffer, buffers, _opts) = msg, state) do
    pad_ref = Message.for_pad(msg)
    PadModel.assert_data!(state, pad_ref, %{direction: :input})

    Membrane.Logger.debug_verbose("""
    Received buffers on pad #{inspect(pad_ref)}
    Buffers: #{inspect(buffers)}
    """)

    {messages, state} = PadModel.get_and_update_data!(state, pad_ref, :sticky_messages, &{&1, []})

    with {:ok, state} <-
           messages
           |> Enum.reverse()
           |> Bunch.Enum.try_reduce(state, fn msg, st -> msg.(st) end) do
      {:ok, state} =
        if PadModel.get_data!(state, pad_ref, :start_of_stream?) do
          {:ok, state}
        else
          EventController.handle_start_of_stream(pad_ref, state)
        end

      BufferController.handle_buffer(pad_ref, buffers, state)
    end
  end

  # Callback invoked on incoming caps
  defp exec(Message.new(:caps, caps, _opts) = msg, state) do
    pad_ref = Message.for_pad(msg)
    PadModel.assert_data!(state, pad_ref, %{direction: :input})

    Logger.debug("""
    Received caps on pad #{inspect(pad_ref)}
    Caps: #{inspect(caps)}
    """)

    CapsController.handle_caps(pad_ref, caps, state)
  end

  # Callback invoked on incoming event
  defp exec(Message.new(:event, event, _opts) = msg, state) do
    pad_ref = Message.for_pad(msg)
    PadModel.assert_instance!(state, pad_ref)

    Membrane.Logger.debug_verbose("""
    Received event on pad #{inspect(pad_ref)}
    Event: #{inspect(event)}
    """)

    do_exec = fn state ->
      EventController.handle_event(pad_ref, event, state)
    end

    if event |> Event.sticky?() do
      state
      |> PadModel.update_data!(pad_ref, :sticky_messages, &[do_exec | &1])
      ~> {:ok, &1}
    else
      do_exec.(state)
    end
  end
end
