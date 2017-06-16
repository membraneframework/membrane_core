defmodule Membrane.Element.State do
  @moduledoc false
  # Structure representing state of an element. It is a part of the private API.
  # It does not represent state of elements you construct, it's a state used
  # internally in Membrane.

  use Membrane.Mixins.Log
  alias Membrane.Pad
  alias __MODULE__
  alias Membrane.PullBuffer


  @type t :: %Membrane.Element.State{
    internal_state: any,
    module: module,
    playback_state: Membrane.Element.playback_state_t,
    source_pads_by_names: %{required(Pad.name_t) => pid},
    source_pads_by_pids: %{required(pid) => Pad.name_t},
    source_pads_pull_demands: %{required(Pad.name_t) => integer},
    sink_pads_by_names: %{required(Pad.name_t) => pid},
    sink_pads_by_pids: %{required(pid) => Pad.name_t},
    sink_pads_pull_buffers: %{required(Pad.name_t) => any},
    sink_pads_self_demands: %{required(Pad.name_t) => non_neg_integer},
    message_bus: pid,
  }

  defstruct \
    internal_state: nil,
    module: nil,
    playback_state: :stopped,
    source_pads_by_pids: %{},
    source_pads_by_names: %{},
    source_pads_pull_demands: %{},
    sink_pads_by_pids: %{},
    sink_pads_by_names: %{},
    sink_pads_pull_buffers: %{},
    sink_pads_self_demands: %{},
    message_bus: nil


  @doc """
  Initializes new state.
  """
  @spec new(module, any) :: t
  def new(module, internal_state) do
    # Initialize source pads
    {source_pads_by_names, source_pads_by_pids, source_pads_pull_demands} =
      if Kernel.function_exported?(module, :known_source_pads, 0) do
        module.known_source_pads else %{}
      end |> spawn_pads(:source)

    # Initialize sink pads
    {sink_pads_by_names, sink_pads_by_pids, sink_pads_pull_data} =
      if Kernel.function_exported?(module, :known_sink_pads, 0) do
        module.known_sink_pads else %{}
      end |> spawn_pads(:sink)

    sink_pads_pull_buffers = sink_pads_pull_data |> Enum.into(%{}, fn {k, {pb, _}} -> {k, pb} end)
    sink_pads_self_demands = sink_pads_pull_data |> Enum.into(%{}, fn {k, {_, sd}} -> {k, sd} end)

    %Membrane.Element.State{
      module: module,
      source_pads_by_names: source_pads_by_names,
      source_pads_by_pids: source_pads_by_pids,
      source_pads_pull_demands: source_pads_pull_demands,
      sink_pads_by_names: sink_pads_by_names,
      sink_pads_by_pids: sink_pads_by_pids,
      sink_pads_pull_buffers: sink_pads_pull_buffers,
      sink_pads_self_demands: sink_pads_self_demands,
      internal_state: internal_state,
    }
  end

  # Spawns pad processes for pads that are always available builds a map of
  # pad names => pad PIDs.
  defp spawn_pads(known_pads, direction) do
    known_pads
      |> Enum.filter(fn({_name, {availability, _mode, _caps}}) ->
        availability == :always
      end)
      |> Enum.map(fn {name, {_availability, mode, _caps}} ->
          pad_module = case mode do
            :pull -> Pad.Mode.Pull
            :push -> Pad.Mode.Push
          end

          {:ok, pid} = Pad.start_link(pad_module, direction)

          pull_data = case direction do
            :source -> 0
            :sink -> {PullBuffer.new(pid, 100), 0}
          end

          {{name, pid}, {pid, name}, {name, pull_data}}
        end)
      |> Membrane.Helper.Enum.unzip!(3)
      |> case do {by_name, by_pid, pull_data} -> {
          by_name |> Enum.into(%{}),
          by_pid |> Enum.into(%{}),
          pull_data |> Enum.into(%{}),
        }
      end
  end

  def get_sink_pull_buffer(%{sink_pads_pull_buffers: pull_buffers}, pad_name) do
    case pull_buffers |> Map.get(pad_name) do
      nil -> {:error, :unknown_pad}
      buf -> {:ok, buf}
    end
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

  defp fill_sink_pull_buffers %State{sink_pads_pull_buffers: pull_buffers} = state do
    {:ok, %State{state | sink_pads_pull_buffers: pull_buffers |> Enum.into(%{}, fn {k, v} -> {k, v |> PullBuffer.fill} end)}}
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
         {:ok, state} <- State.activate_pads(state),
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
    with {:ok, state} <- log_playback_state_changing(old, new, target, state),
         {:ok, %State{internal_state: internal_state} = state} <- State.deactivate_pads(state),
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
