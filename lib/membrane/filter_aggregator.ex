defmodule Membrane.FilterAggregator do
  @moduledoc """
  An element allowing to aggregate many filters within one Elixir process.

  This element supports only filters with one input and one output
  with following restrictions:
  * not using timers
  * (To be fixed) not relying on callback contexts
  * not relying on received messages
  * their pads have to be named `:input` and `:output`
  """
  use Membrane.Filter

  def_options filters: [
                spec: [module() | struct()],
                description: "A list of filters applied to incoming stream"
              ]

  def_input_pad :input,
    caps: :any,
    demand_unit: :buffers

  def_output_pad :output,
    caps: :any

  @impl true
  def handle_init(%__MODULE__{filters: filter_specs}) do
    states =
      filter_specs
      |> Enum.map(fn
        {name, %module{} = sub_opts} ->
          struct = struct!(module, sub_opts |> Map.from_struct())
          {:ok, state} = module.handle_init(struct)
          {name, module, state}

        {name, module} ->
          options =
            module
            |> Code.ensure_loaded!()
            |> function_exported?(:__struct__, 1)
            |> case do
              true -> struct!(module, [])
              false -> %{}
            end

          {:ok, state} = module.handle_init(options)
          {name, module, state}
      end)

    {:ok, %{states: states}}
  end

  @impl true
  def handle_stopped_to_prepared(_ctx, %{states: states}) do
    {actions, states} = pipe_downstream([:stopped_to_prepared], states)
    actions = List.delete(actions, :stopped_to_prepared)
    {{:ok, actions}, %{states: states}}
  end

  @impl true
  def handle_prepared_to_playing(_ctx, %{states: states}) do
    {actions, states} = pipe_downstream([:prepared_to_playing], states)
    actions = List.delete(actions, :prepared_to_playing)
    {{:ok, actions}, %{states: states}}
  end

  @impl true
  def handle_playing_to_prepared(_ctx, %{states: states}) do
    {actions, states} = pipe_downstream([:playing_to_prepared], states)
    actions = List.delete(actions, :playing_to_prepared)
    {{:ok, actions}, %{states: states}}
  end

  @impl true
  def handle_prepared_to_stopped(_ctx, %{states: states}) do
    {actions, states} = pipe_downstream([:prepared_to_stopped], states)
    actions = List.delete(actions, :prepared_to_stopped)
    {{:ok, actions}, %{states: states}}
  end

  @impl true
  def handle_start_of_stream(:input, _ctx, %{states: states}) do
    {actions, states} = pipe_downstream([start_of_stream: :output], states)
    actions = Keyword.delete(actions, :start_of_stream)

    {{:ok, actions}, %{states: states}}
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, %{states: states}) do
    {actions, states} = pipe_downstream([end_of_stream: :output], states)

    {{:ok, actions}, %{states: states}}
  end

  @impl true
  def handle_caps(:input, caps, _ctx, %{states: states}) do
    {actions, states} = pipe_downstream([caps: {:output, caps}], states)
    {{:ok, actions}, %{states: states}}
  end

  @impl true
  def handle_demand(:output, size, :buffers, _ctx, %{states: states}) do
    {actions, states} = pipe_upstream([demand: {:input, size}], states)
    {{:ok, actions}, %{states: states}}
  end

  @impl true
  def handle_process(:input, _buffer, _ctx, states) do
    {:ok, states}
  end

  @impl true
  def handle_process_list(:input, buffers, _ctx, %{states: states}) do
    {actions, states} = pipe_downstream([buffer: {:output, buffers}], states)

    {{:ok, actions}, %{states: states}}
  end

  defp pipe_upstream(downstream_actions, states) do
    {states, actions} =
      states
      |> Enum.reverse()
      |> Enum.map_reduce(downstream_actions, fn {name, module, state}, actions ->
        {actions, next_state} = perform_actions(actions, module, state, [])

        {{name, module, next_state}, actions}
      end)

    {actions, Enum.reverse(states)}
  end

  defp pipe_downstream(initial_actions, states) do
    {states, actions} =
      states
      |> Enum.map_reduce(initial_actions, fn {name, module, state}, actions ->
        {actions, next_state} = perform_actions(actions, module, state, [])

        {{name, module, next_state}, actions}
      end)

    {actions, states}
  end

  defp perform_actions([], _module, state, next_actions_acc) do
    {next_actions_acc |> Enum.reverse() |> List.flatten(), state}
  end

  defp perform_actions([{:forward, data} | actions], module, state, next_actions_acc) do
    action =
      case data do
        %Membrane.Buffer{} ->
          {:buffer, {:output, data}}

        [%Membrane.Buffer{} | _tail] ->
          {:buffer, {:output, data}}

        :end_of_stream ->
          {:end_of_stream, :output}

        %_struct{} ->
          cond do
            Membrane.Event.event?(data) -> {:event, {:output, data}}
            true -> {:caps, {:output, data}}
          end
      end

    perform_actions([action | actions], module, state, next_actions_acc)
  end

  defp perform_actions([action | actions], module, state, next_actions_acc) do
    case perform_action(action, module, state) do
      # Perform splitted actions within the same element
      {{:ok, [{:split, _action} | _tail] = next_actions}, next_state} ->
        perform_actions(
          next_actions ++ actions,
          module,
          next_state,
          next_actions_acc
        )

      {{:ok, next_actions}, next_state} when is_list(next_actions) ->
        perform_actions(actions, module, next_state, [next_actions | next_actions_acc])

      {:ok, next_state} ->
        perform_actions(actions, module, next_state, next_actions_acc)

      term ->
        raise "Invalid return from callback: #{inspect(term)}"
    end
  end

  defp perform_action({:buffer, {:output, buffer}}, module, state) do
    if is_list(buffer) do
      module.handle_process_list(:input, buffer, %{}, state)
    else
      module.handle_process(:input, buffer, %{}, state)
    end
  end

  defp perform_action({:caps, {:output, caps}}, module, state) do
    module.handle_caps(:input, caps, %{}, state)
  end

  defp perform_action({:event, {:output, event}}, module, state) do
    module.handle_event(:input, event, %{}, state)
  end

  # Pseudo-action that doesn't exist used to trigger handle_start_of_stream
  defp perform_action({:start_of_stream, :output}, module, state) do
    {{:ok, actions}, new_state} =
      case module.handle_start_of_stream(:input, %{}, state) do
        {:ok, state} -> {{:ok, []}, state}
        result -> result
      end

    {{:ok, Keyword.put_new(actions, :start_of_stream, :output)}, new_state}
  end

  defp perform_action({:end_of_stream, :output}, module, state) do
    module.handle_end_of_stream(:input, %{}, state)
  end

  defp perform_action({:demand, {:input, size}}, module, state) do
    # If downstream demands on input, we'd receive that on output
    # TODO: how to handle demand size unit
    module.handle_demand(:output, size, :buffers, %{}, state)
  end

  defp perform_action({:redemand, :output}, _module, state) do
    # Pass the action downstream, it may come back as a handle_demand call in FilterStage
    {{:ok, redemand: :output}, state}
  end

  defp perform_action({:notify, message}, _module, state) do
    # Pass the action downstream
    {{:ok, notify: message}, state}
  end

  defp perform_action({:split, {:handle_process, args_lists}}, module, state) do
    {{:ok, actions}, state} =
      args_lists
      |> Bunch.Enum.try_flat_map_reduce(state, fn [:input, buffer], acc_state ->
        case module.handle_process(:input, buffer, %{}, acc_state) do
          {:ok, state} -> {{:ok, []}, state}
          result -> result
        end
      end)

    # instead of redemands from splitted callback calls, put one after all other actions
    actions =
      actions
      |> Enum.split_with(fn
        {:redemand, _pad} -> true
        _other -> false
      end)
      |> case do
        {[], actions} -> actions
        {_redemands, actions} -> actions ++ [redemand: :output]
      end

    {{:ok, actions}, state}
  end

  # Playback state change actions. They use pseudo-action to invoke proper callback in following element
  defp perform_action(action, module, state)
       when action in [
              :stopped_to_prepared,
              :prepared_to_playing,
              :playing_to_prepared,
              :prepared_to_stopped
            ] do
    perform_playback_change(action, module, state)
  end

  defp perform_action({:latency, _latency}, _module, _state) do
    raise "latency action not supported in #{inspect(__MODULE__)}"
  end

  defp perform_playback_change(pseudo_action, module, state) do
    callback =
      case pseudo_action do
        :stopped_to_prepared -> :handle_stopped_to_prepared
        :prepared_to_playing -> :handle_prepared_to_playing
        :playing_to_prepared -> :handle_playing_to_prepared
        :prepared_to_stopped -> :handle_prepared_to_stopped
      end

    {{:ok, actions}, new_state} =
      case apply(module, callback, [%{}, state]) do
        {:ok, state} -> {{:ok, []}, state}
        result -> result
      end

    {{:ok, actions ++ [pseudo_action]}, new_state}
  end
end
