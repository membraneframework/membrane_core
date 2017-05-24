defmodule Membrane.Element.State do
  @moduledoc false
  # Structure representing state of an element. It is a part of the private API.
  # It does not represent state of elements you construct, it's a state used
  # internally in Membrane.

  use Membrane.Mixins.Log
  alias Membrane.Pad
  alias __MODULE__


  @type t :: %Membrane.Element.State{
    internal_state: any,
    module: module,
    playback_state: Membrane.Element.playback_state_t,
    source_pads_by_names: %{required(Pad.name_t) => pid},
    source_pads_by_pids: %{required(pid) => Pad.name_t},
    sink_pads_by_names: %{required(Pad.name_t) => pid},
    sink_pads_by_pids: %{required(pid) => Pad.name_t},
    sink_pads_pull_buffers: %{required(pid) => any},
    message_bus: pid,
  }

  defstruct \
    internal_state: nil,
    module: nil,
    playback_state: :stopped,
    source_pads_by_pids: %{},
    source_pads_by_names: %{},
    sink_pads_by_pids: %{},
    sink_pads_by_names: %{},
    sink_pads_pull_buffers: %{},
    message_bus: nil


  @doc """
  Initializes new state.
  """
  @spec new(module, any) :: t
  def new(module, internal_state) do
    # Initialize source pads
    {source_pads_by_names, source_pads_by_pids} =
      if Kernel.function_exported?(module, :known_source_pads, 0) do
        module.known_source_pads() |> spawn_pads(:source)
      else
        {%{}, %{}}
      end

    # Initialize sink pads
    {sink_pads_by_names, sink_pads_by_pids, sink_pads_pull_buffers} =
      if Kernel.function_exported?(module, :known_sink_pads, 0) do
        module.known_sink_pads() |> spawn_pads(:sink)
      else
        {%{}, %{}}
      end

    %Membrane.Element.State{
      module: module,
      source_pads_by_names: source_pads_by_names,
      source_pads_by_pids: source_pads_by_pids,
      sink_pads_by_names: sink_pads_by_names,
      sink_pads_by_pids: sink_pads_by_pids,
      sink_pads_pull_buffers: sink_pads_pull_buffers,
      internal_state: internal_state,
    }
  end

  # Spawns pad processes for pads that are always available builds a map of
  # pad names => pad PIDs.
  defp spawn_pads(known_pads, direction) do
    pads = known_pads
      |> Map.to_list
      |> Enum.filter(fn({_name, {availability, _mode, _caps}}) ->
        availability == :always
      end)
    {by_name, by_pid} = pads
      |> Enum.reduce({%{}, %{}}, fn({name, {_availability, mode, _caps}}, {acc_by_names, acc_by_pids}) ->
        pad_module = case mode do
          :pull -> Pad.Mode.Pull
          :push -> Pad.Mode.Push
        end

        {:ok, pid} = Pad.start_link(pad_module, direction)

        {acc_by_names |> Map.put(name, pid), acc_by_pids |> Map.put(pid, name)}
      end)
    case direction do
      :source -> {by_name, by_pid}
      :sink ->
        pull_buffers = pads
          |> Enum.filter(fn {_name, {_av, mode, _caps}} -> mode == :pull end)
          |> Enum.into(%{}, fn {name, _opts} ->
            %{^name => pid} = by_name
            {pid, [queue: IOQueue.new, init_buf_min_size: 0, buf_size: 100]}
          end)
        {by_name, by_pid, pull_buffers}
    end
  end


  def get_pad_pull_buffer(state, pad_pid) do
    with \
      
  end

  @doc """
  Finds pad name associated with given PID.

  On success returns `{:ok, pad_name}`.

  If pad with given PID is now known, returns `{:error, :unknown_pad}`.
  """
  @spec get_pad_name_by_pid(t, Pad.direction_t, pid) ::
    {:ok, pid} |
    {:error, any}
  def get_pad_name_by_pid(state, pad_direction, pad_pid) do
    case pad_direction do
      :source ->
        case state.source_pads_by_pids |> Map.get(pad_pid) do
          nil ->
            {:error, :unknown_pad}

          name ->
            {:ok, name}
        end

      :sink ->
        case state.sink_pads_by_pids |> Map.get(pad_pid) do
          nil ->
            {:error, :unknown_pad}

          name ->
            {:ok, name}
        end
    end
  end



  @doc """
  Finds pad mode associated with given name.

  On success returns `{:ok, {availability, direction, mode, pid}}`.

  If pad with given name is now known, returns `{:error, :unknown_pad}`.
  """
  @spec get_pad_by_name(t, Pad.direction_t, Pad.name_t) ::
    {:ok, {Membrane.Pad.availability_t, Membrane.Pad.direction_t, Membrane.Pad.mode_t, pid}} |
    {:error, any}
  def get_pad_by_name(%State{module: module} = state, pad_direction, pad_name) do
    case pad_direction do
      :source ->
        case state.source_pads_by_names |> Map.get(pad_name) do
          nil ->
            {:error, :unknown_pad}

          pid ->
            {availability, mode, _caps} = module.known_source_pads |> Map.get(pad_name)
            {:ok, {availability, pad_direction, mode, pid}}
        end

      :sink ->
        case state.sink_pads_by_names |> Map.get(pad_name) do
          nil ->
            {:error, :unknown_pad}

            pid ->
              {availability, mode, _caps} = module.known_sink_pads |> Map.get(pad_name)
              {:ok, {availability, pad_direction, mode, pid}}
        end
    end
  end


  @doc """
  Activates all pads.

  Returns `{:ok, new_state}`.
  """
  @spec activate_pads(t) :: :ok | {:error, any}
  def activate_pads(state) do
    # TODO add error checking
    activate_pads_by_pids(state, state.source_pads_by_pids |> Map.keys)
    activate_pads_by_pids(state, state.sink_pads_by_pids |> Map.keys)
  end


  defp activate_pads_by_pids(state, []), do: {:ok, state}

  defp activate_pads_by_pids(state, [head|tail]) do
    Pad.activate(head)
    activate_pads_by_pids(state, tail)
  end


  @doc """
  Deactivates all pads.

  Returns `{:ok, new_state}`.
  """
  @spec deactivate_pads(t) :: :ok | {:error, any}
  def deactivate_pads(state) do
    # TODO add error checking
    deactivate_pads_by_pids(state, state.source_pads_by_pids |> Map.keys)
    deactivate_pads_by_pids(state, state.sink_pads_by_pids |> Map.keys)
  end


  defp deactivate_pads_by_pids(state, []), do: {:ok, state}

  defp deactivate_pads_by_pids(state, [head|tail]) do
    Pad.deactivate(head)
    deactivate_pads_by_pids(state, tail)
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
         {:ok, state} <- module.base_module.handle_actions(actions, %{state | internal_state: new_internal_state}),
         {:ok, state} <- log_playback_state_changed(old, new, target, %{state | internal_state: new_internal_state, playback_state: new})
    do
      {:ok, state}

    else
      {:error, {reason, state}} ->
        warn("Failed to change playback state: old = #{inspect(old)}, new = #{inspect(new)}, target = #{inspect(target)}, reason = #{inspect(reason)}")
        {:error, {reason, state}}
    end
  end

  def change_playback_state(%State{module: module} = state, :prepared = old, :playing = new, target) do
    with {:ok, state} <- log_playback_state_changing(old, new, target, state),
         {:ok, %State{internal_state: internal_state} = state} <- State.activate_pads(state),
         {:ok, {actions, new_internal_state}} <- module.handle_play(internal_state),
         {:ok, state} <- module.base_module.handle_actions(actions, %{state | internal_state: new_internal_state}),
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
    with {:ok, state} <- log_playback_state_changing(old, new, target, state),
         {:ok, %State{internal_state: internal_state} = state} <- State.deactivate_pads(state),
         {:ok, {actions, new_internal_state}} <- module.handle_prepare(old, internal_state),
         {:ok, state} <- module.base_module.handle_actions(actions, %{state | internal_state: new_internal_state}),
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
         {:ok, state} <- module.base_module.handle_actions(actions, %{state | internal_state: new_internal_state}),
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
