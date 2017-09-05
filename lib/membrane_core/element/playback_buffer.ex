defmodule Membrane.Element.PlaybackBuffer do
  alias __MODULE__
  alias Membrane.Element.State
  use Membrane.Helper
  use Membrane.Mixins.Log, tags: :core

  defstruct \
    q: nil

  @qe Qex

  def new do
    %PlaybackBuffer{q: @qe.new}
  end

  def store(msg, %State{playback_state: :playing} = state), do: exec(msg, state)

  def store({type, _args} = msg, state)
  when type in [:membrane_event, :membrane_caps]
  do
    exec(msg, state)
      |> provided(that: state.playback_buffer |> empty?, else:
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

  def eval(state) do
    with \
      {:ok, state} <- state.playback_buffer.q
        |> Helper.Enum.reduce_with(state, &exec/2),
    do: {:ok, state |> Helper.Struct.put_in([:playback_buffer, :q], @qe.new)}
  end

  def empty?(%PlaybackBuffer{q: q}), do: q |> Enum.empty?

  # Callback invoked on demand request coming from the source pad in the pull mode
  defp exec({:membrane_demand, [size, pad_name]}, %State{module: module} = state) do
    {:ok, _} = state |> State.get_pad_data(:source, pad_name)
    demand = if size == 0 do "dumb demand" else "demand of size #{inspect size}" end
    debug "Received #{demand} on pad #{inspect pad_name}"
    module.base_module.handle_demand(pad_name, size, state)
  end

  # Callback invoked on buffer coming from the sink pad to the sink
  defp exec({:membrane_buffer, [buffers, pad_name]}, %State{module: module} = state) do
    {:ok, %{mode: mode}} = state |> State.get_pad_data(:sink, pad_name)
    debug """
      Received buffers on pad #{inspect pad_name}
      Buffers: #{inspect buffers}
      """
    module.base_module.handle_buffer(mode, pad_name, buffers, state)
  end

  # Callback invoked on incoming caps
  defp exec({:membrane_caps, [caps, pad_name]}, %State{module: module} = state) do
    {:ok, %{mode: mode}} = state |> State.get_pad_data(:sink, pad_name)
    debug """
      Received caps on pad #{inspect pad_name}
      Caps: #{inspect caps}
      """
    module.base_module.handle_caps(mode, pad_name, caps, state)
  end

  # Callback invoked on incoming event
  defp exec({:membrane_event, [event, pad_name]}, %State{module: module} = state) do
    {:ok, %{mode: mode, direction: direction}} = state |> State.get_pad_data(:any, pad_name)
    debug """
      Received event on pad #{inspect pad_name}
      Event: #{inspect event}
      """
    module.base_module.handle_event(mode, direction, pad_name, event, state)
  end

end
