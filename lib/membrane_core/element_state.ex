defmodule Membrane.Element.State do
  @moduledoc false
  # Structure representing state of an element. It is a part of the private API.
  # It does not represent state of elements you construct, it's a state used
  # internally in Membrane.

  @type t :: %Membrane.Element.State{
    internal_state: any,
    module: module,
    playback_state: :stopped | :prepared | :playing,
    source_pads: any, # FIXME
    sink_pads: any, # FIXME
    message_bus: pid,
  }

  defstruct \
    internal_state: nil,
    module: nil,
    playback_state: :stopped,
    source_pads: %{},
    sink_pads: %{},
    message_bus: nil


  @spec new(module, any) :: t
  def new(module, internal_state) do
    # Determine initial list of source pads
    source_pads = if Membrane.Element.is_source?(module) do
      module.known_source_pads() |> known_pads_to_pads_state
    else
      %{}
    end

    # Determine initial list of sink pads
    sink_pads = if Membrane.Element.is_sink?(module) do
      module.known_sink_pads() |> known_pads_to_pads_state
    else
      %{}
    end

    %Membrane.Element.State{
      module: module,
      source_pads: source_pads,
      sink_pads: sink_pads,
      internal_state: internal_state,
    }
  end


  @spec set_source_pad_peer(t, Membrane.Pad.name_t, pid, Membrane.Pad.name_t) :: {:ok, t} | {:error, any}
  def set_source_pad_peer(state, source_pad_name, destination_pid, destination_pad_name) do
    case state.source_pads |> Map.get(source_pad_name) do
      nil ->
        {:error, :unknown_pad}

      pad_state ->
        new_pad_state = pad_state |> Map.put(:peer, {destination_pid, destination_pad_name})
        new_source_pads = state.source_pads |> Map.put(source_pad_name, new_pad_state)

        {:ok, %{state | source_pads: new_source_pads}}
    end
  end


  @spec get_source_pad_peer(t, Membrane.Pad.name_t) :: {:ok, {pid, Membrane.Pad.name_t} | nil} | {:error, any}
  def get_source_pad_peer(state, source_pad_name) do
    case state.source_pads |> Map.get(source_pad_name) do
      nil ->
        {:error, :unknown_pad}

      %{peer: peer} ->
        {:ok, peer}
    end
  end


  @spec set_sink_pad_peer(t, Membrane.Pad.name_t, pid, Membrane.Pad.name_t) :: {:ok, t} | {:error, any}
  def set_sink_pad_peer(state, sink_pad_name, source_pid, source_pad_name) do
    case state.sink_pads |> Map.get(sink_pad_name) do
      nil ->
        {:error, :unknown_pad}

      pad_state ->
        new_pad_state = pad_state |> Map.put(:peer, {source_pid, source_pad_name})
        new_sink_pads = state.sink_pads |> Map.put(sink_pad_name, new_pad_state)

        {:ok, %{state | sink_pads: new_sink_pads}}
    end
  end


  @spec get_sink_pad_peer(t, Membrane.Pad.name_t) :: {:ok, {pid, Membrane.Pad.name_t} | nil} | {:error, any}
  def get_sink_pad_peer(state, sink_pad_name) do
    case state.sink_pads |> Map.get(sink_pad_name) do
      nil ->
        {:error, :unknown_pad}

      %{peer: peer} ->
        {:ok, peer}
    end
  end


  @spec set_source_pad_caps(t, Membrane.Pad.name_t, Membrane.Caps.t) :: {:ok, t} | {:error, any}
  def set_source_pad_caps(state, source_pad_name, caps) do
    case state.source_pads |> Map.get(source_pad_name) do
      nil ->
        {:error, :unknown_pad}

      pad_state ->
        new_pad_state = pad_state |> Map.put(:caps, caps)
        new_source_pads = state.source_pads |> Map.put(source_pad_name, new_pad_state)

        {:ok, %{state | source_pads: new_source_pads}}
    end
  end


  @spec get_source_pad_caps(t, Membrane.Pad.name_t) :: {:ok, Membrane.Caps.t | nil} | {:error, any}
  def get_source_pad_caps(state, source_pad_name) do
    case state.source_pads |> Map.get(source_pad_name) do
      nil ->
        {:error, :unknown_pad}

      %{caps: caps} ->
        {:ok, caps}
    end
  end


  @spec set_sink_pad_caps(t, Membrane.Pad.name_t, Membrane.Caps.t) :: {:ok, t} | {:error, any}
  def set_sink_pad_caps(state, sink_pad_name, caps) do
    case state.sink_pads |> Map.get(sink_pad_name) do
      nil ->
        {:error, :unknown_pad}

      pad_state ->
        new_pad_state = pad_state |> Map.put(:caps, caps)
        new_sink_pads = state.sink_pads |> Map.put(sink_pad_name, new_pad_state)

        {:ok, %{state | sink_pads: new_sink_pads}}
    end
  end


  @spec get_sink_pad_caps(t, Membrane.Pad.name_t) :: {:ok, Membrane.Caps.t | nil} | {:error, any}
  def get_sink_pad_caps(state, sink_pad_name) do
    case state.sink_pads |> Map.get(sink_pad_name) do
      nil ->
        {:error, :unknown_pad}

      %{caps: caps} ->
        {:ok, caps}
    end
  end


  # Converts list of known pads into map of pad states.
  defp known_pads_to_pads_state(known_pads) do
    known_pads
    |> Map.to_list
    |> Enum.filter(fn({_name, {availability, _caps}}) ->
      availability == :always
    end)
    |> Enum.reduce(%{}, fn({name, {_availability, _caps}}, acc) ->
      acc |> Map.put(name, %{peer: nil, caps: nil})
    end)
  end
end
