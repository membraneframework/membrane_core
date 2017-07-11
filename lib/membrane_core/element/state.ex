defmodule Membrane.Element.State do
  @moduledoc false
  # Structure representing state of an element. It is a part of the private API.
  # It does not represent state of elements you construct, it's a state used
  # internally in Membrane.

  use Membrane.Mixins.Log
  alias __MODULE__
  alias Membrane.PullBuffer
  alias Membrane.Element
  use Membrane.Helper

  @type t :: %Membrane.Element.State{
    internal_state: any,
    module: module,
    playback_state: Membrane.Element.playback_state_t,
    pads: %{optional(Element.pad_name_t) => pid},
    message_bus: pid,
  }

  defstruct \
    internal_state: nil,
    module: nil,
    playback_state: :stopped,
    pads: %{},
    message_bus: nil


  @doc """
  Initializes new state.
  """
  @spec new(module, any) :: t
  def new(module, internal_state) do
    # Initialize source pads

    pads_data = Map.merge(
        handle_known_pads(:known_sink_pads, :sink, module),
        handle_known_pads(:known_source_pads, :source, module)
      )

    pad_names_by_pids = pads_data
      |> Enum.into(%{}, fn {name, %{pid: pid}} -> {pid, name} end)

    %Membrane.Element.State{
      module: module,
      pads: %{data: pads_data, names_by_pids: pad_names_by_pids},
      internal_state: internal_state,
    }
  end

  defp handle_known_pads(known_pads_fun, direction, module) do
    known_pads = cond do
      function_exported? module, known_pads_fun , 0 ->
        apply module, known_pads_fun, []
      true -> %{}
    end
    known_pads
      |> Enum.flat_map(fn params -> init_pad_data params, direction end)
      |> Enum.into(%{})
  end

  defp init_pad_data({name, {:always, mode, caps}}, direction) do
    data = %{
        name: name, pid: nil, mode: mode,direction: direction,
        caps: nil, accepted_caps: caps,
      }
    [{name, data}]
  end
  defp init_pad_data(_params, _direction), do: []

  def get_pads_data(state, direction \\ :any)
  def get_pads_data(state, :any), do: state.pads.data
  def get_pads_data(state, direction), do: state.pads.data
    |> Enum.filter(fn {_, %{direction: ^direction}} -> true; _ -> false end)
    |> Enum.into(%{})

  def get_pad_data(state, pad_direction, pad_pid, keys \\ [])
  def get_pad_data(state, pad_direction, pad_pid, keys) when is_pid pad_pid do
    with {:ok, pad_name} <-
      state.pads.names_by_pids |> Helper.Map.get_wrap(pad_pid, :unknown_pad)
    do get_pad_data(state, pad_direction, pad_name, keys)
    end
  end
  def get_pad_data(state, pad_direction, pad_name, []) do
    with %{direction: dir} = data when pad_direction in [:any, dir] <-
      state.pads.data |> Map.get(pad_name)
    do {:ok, data}
    else _ -> {:error, :unknown_pad}
    end
  end
  def get_pad_data(state, pad_direction, pad_name, keys) do
    with {:ok, pad_data} <- get_pad_data(state, pad_direction, pad_name)
    do {:ok, pad_data |> Helper.Map.get_in(keys)}
    end
  end

  def get_pad_data!(state, pad_direction, pad_name, keys \\ []), do:
    get_pad_data(state, pad_direction, pad_name, keys)
      ~> ({:ok, pad_data} -> pad_data)

  def update_pad_data(state, pad_direction, pad_name, keys \\ [], f)
  def update_pad_data(state, pad_direction, pad_name, keys, f) do
    with \
      {:ok, pad_data} <- get_pad_data(state, pad_direction, pad_name),
      {:ok, pad_data} <- pad_data
        |> Helper.Map.get_and_update_in(keys, &case f.(&1) do
            {:ok, res} -> {:ok, res}
            {:error, reason} -> {{:error, reason}, nil}
          end)
    do {:ok, state |> Helper.Struct.put_in([:pads, :data, pad_name], pad_data)}
    else
      {{:error, reason}, _pd} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  def set_pad_data(state, pad_direction, pad_name, keys \\ [], v), do:
    update_pad_data(state, pad_direction, pad_name, keys, fn _ -> {:ok, v} end)

  def get_update_pad_data(state, pad_direction, pad_name, keys \\ [], f)
  def get_update_pad_data(state, pad_direction, pad_name, keys, f) do
    with \
      {:ok, pad_data} <- get_pad_data(state, pad_direction, pad_name),
      {{:ok, out}, pad_data} <- pad_data
        |> Helper.Map.get_and_update_in(keys, &case f.(&1) do
            {:ok, {out, res}} -> {{:ok, out}, res}
            {:error, reason} -> {{:error, reason}, nil}
          end)
    do {:ok, {out, state |> Helper.Struct.put_in([:pads, :data, pad_name], pad_data)}}
    else
      {{:error, reason}, _pd} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end


  defp fill_sink_pull_buffers(state) do
    state
      |> State.get_pads_data(:sink)
      |> Map.keys
      |> Helper.Enum.reduce_with(state, fn pad_name, st ->
        update_pad_data st, :sink, pad_name, :buffer, &PullBuffer.fill/1
      end)
      |> or_warn_error("Unable to fill sink pull buffers")
  end


  @doc """
  Changes playback state.

  On success returns `{:ok, new_state}`.

  On failure returns `{:error, {reason, new_state}}`.
  """
  @spec change_playback_state(t, Element.playback_state_t, Element.playback_state_t, Element.playback_state_t) ::
    {:ok, State.t} |
    {:error, {any, State.t}}

  def change_playback_state(state, old, new, _target) when old == new, do: {:ok, state}

  def change_playback_state(%State{module: module} = state, :stopped = old, :prepared = new, target) do
    with {:ok, %State{internal_state: internal_state} = state} <- log_playback_state_changing(old, new, target, state),
         {:ok, {actions, new_internal_state}} <- module.handle_prepare(old, internal_state),
         {:ok, state} <- module.base_module.handle_actions(actions, :handle_prepare, %{state | internal_state: new_internal_state}),
         {:ok, state} <- log_playback_state_changed(old, new, target, %{state | playback_state: new})
    do
      {:ok, state}

    else
      {:error, {reason, state}} ->
        warn("Failed to change playback state: old = #{inspect(old)}, new = #{inspect(new)}, target = #{inspect(target)}, reason = #{inspect(reason)}")
        {:error, {reason, state}}
    end
  end

  def change_playback_state(%State{module: module} = state, :prepared = old, :playing = new, target) do
    with {:ok, %State{internal_state: internal_state} = state} <- log_playback_state_changing(old, new, target, state),
         {:ok, {actions, new_internal_state}} <- module.handle_play(internal_state),
         {:ok, state} <- fill_sink_pull_buffers(state),
         {:ok, state} <- module.base_module.handle_actions(actions, :handle_play, %{state | internal_state: new_internal_state}),
         {:ok, state} <- log_playback_state_changed(old, new, target, %{state | playback_state: new})
    do
      {:ok, state}

    else
      {:error, {reason, state}} ->
        warn("Failed to change playback state: old = #{inspect(old)}, new = #{inspect(new)}, target = #{inspect(target)}, reason = #{inspect(reason)}")
        {:error, {reason, state}}
    end
  end

  def change_playback_state(%State{module: module} = state, :playing = old, :prepared = new, target) do
    with {:ok, %State{internal_state: internal_state} = state} <- log_playback_state_changing(old, new, target, state),
         {:ok, {actions, new_internal_state}} <- module.handle_prepare(old, internal_state),
         {:ok, state} <- module.base_module.handle_actions(actions, :handle_prepare, %{state | internal_state: new_internal_state}),
         {:ok, state} <- log_playback_state_changed(old, new, target, %{state | playback_state: new})
    do
     {:ok, state}

    else
      {:error, {reason, state}} ->
        warn("Failed to change playback state: old = #{inspect(old)}, new = #{inspect(new)}, target = #{inspect(target)}, reason = #{inspect(reason)}")
        {:error, {reason, state}}
    end
  end

  def change_playback_state(%State{module: module} = state, :prepared = old, :stopped = new, target) do
    with {:ok, %State{internal_state: internal_state} = state} <- log_playback_state_changing(old, new, target, state),
         {:ok, {actions, new_internal_state}} <- module.handle_stop(internal_state),
         {:ok, state} <- module.base_module.handle_actions(actions, :handle_stop, %{state | internal_state: new_internal_state}),
         {:ok, state} <- log_playback_state_changed(old, new, target, %{state | playback_state: new})
    do
     {:ok, state}

    else
      {:error, {reason, state}} ->
        warn("Failed to change playback state: old = #{inspect(old)}, new = #{inspect(new)}, target = #{inspect(target)}, reason = #{inspect(reason)}")
        {:error, {reason, state}}
    end
  end

  def change_playback_state(state, :stopped, :playing, :playing) do
    with {:ok, state} <- State.change_playback_state(state, :stopped, :prepared, :playing),
         {:ok, state} <- State.change_playback_state(state, :prepared, :playing, :playing)
    do
      {:ok, state}

    else
      {:error, {reason, state}} ->
        {:error, {reason, state}}
    end
  end

  def change_playback_state(state, :playing, :stopped, :stopped) do
    with {:ok, state} <- State.change_playback_state(state, :playing, :prepared, :stopped),
         {:ok, state} <- State.change_playback_state(state, :prepared, :stopped, :stopped)
    do
      {:ok, state}

    else
      {:error, {reason, state}} ->
        {:error, {reason, state}}
    end
  end


  defp log_playback_state_changing(old, new, target, state) do
    debug("Changing playback state: old = #{inspect(old)}, new = #{inspect(new)}, target = #{inspect(target)}, state = #{inspect(state)}")
    {:ok, state}
  end


  defp log_playback_state_changed(old, new, target, state) do
    debug("Changed playback state: old = #{inspect(old)}, new = #{inspect(new)}, target = #{inspect(target)}, state = #{inspect(state)}")
    {:ok, state}
  end
end
