defmodule Membrane.FilterAggregator do
  @moduledoc """
  An element allowing to aggregate many filters within one Elixir process.

  This element supports only filters with one input and one output
  with following restrictions:
  * not using timers
  * not relying on received messages
  * their pads have to be named `:input` and `:output`
  * The first filter must make demands in buffers
  """
  use Membrane.Filter

  alias __MODULE__.Context
  alias Membrane.Element.CallbackContext

  def_options filters: [
                spec: [{String.t(), module() | struct()}],
                description: "A list of filters applied to incoming stream"
              ]

  def_input_pad :input,
    caps: :any,
    demand_mode: :auto,
    demand_unit: :buffers

  def_output_pad :output,
    demand_mode: :auto,
    caps: :any

  @impl true
  def handle_init(%__MODULE__{filters: filter_specs}) do
    states =
      filter_specs
      |> Enum.map(fn
        {name, %module{} = sub_opts} ->
          options = struct!(module, Map.from_struct(sub_opts))
          {name, module, options}

        {name, module} ->
          options =
            module
            |> Code.ensure_loaded!()
            |> function_exported?(:__struct__, 1)
            |> case do
              true -> struct!(module, [])
              false -> %{}
            end

          {name, module, options}
      end)
      |> Enum.map(fn {name, module, options} ->
        {:ok, state} = module.handle_init(options)
        context = Context.build_context!(name, module)
        {name, module, context, state}
      end)

    {:ok, %{states: states}}
  end

  @impl true
  def handle_stopped_to_prepared(agg_ctx, %{states: states}) do
    contexts = states |> Enum.map(&elem(&1, 2))
    prev_contexts = contexts |> List.insert_at(-1, agg_ctx)
    next_contexts = [agg_ctx | contexts]

    states =
      [prev_contexts, states, next_contexts]
      |> Enum.zip_with(fn [prev_context, {name, module, context, state}, next_context] ->
        context = Context.link_contexts(context, prev_context, next_context)
        {name, module, context, state}
      end)

    {actions, states} = pipe_downstream([:stopped_to_prepared], states)
    actions = reject_internal_actions(actions)
    {{:ok, actions}, %{states: states}}
  end

  @impl true
  def handle_prepared_to_playing(_ctx, %{states: states}) do
    {actions, states} = pipe_downstream([:prepared_to_playing], states)
    actions = reject_internal_actions(actions)
    {{:ok, actions}, %{states: states}}
  end

  @impl true
  def handle_playing_to_prepared(_ctx, %{states: states}) do
    {actions, states} = pipe_downstream([:playing_to_prepared], states)
    actions = reject_internal_actions(actions)
    {{:ok, actions}, %{states: states}}
  end

  @impl true
  def handle_prepared_to_stopped(_ctx, %{states: states}) do
    {actions, states} = pipe_downstream([:prepared_to_stopped], states)
    actions = reject_internal_actions(actions)
    {{:ok, actions}, %{states: states}}
  end

  @impl true
  def handle_start_of_stream(:input, _ctx, %{states: states}) do
    {actions, states} = pipe_downstream([start_of_stream: :output], states)
    actions = reject_internal_actions(actions)

    {{:ok, actions}, %{states: states}}
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, %{states: states}) do
    {actions, states} = pipe_downstream([end_of_stream: :output], states)
    actions = reject_internal_actions(actions)

    {{:ok, actions}, %{states: states}}
  end

  @impl true
  def handle_caps(:input, caps, _ctx, %{states: states}) do
    {actions, states} = pipe_downstream([caps: {:output, caps}], states)
    actions = reject_internal_actions(actions)
    {{:ok, actions}, %{states: states}}
  end

  @impl true
  def handle_process_list(:input, buffers, _ctx, %{states: states}) do
    {actions, states} = pipe_downstream([buffer: {:output, buffers}], states)
    actions = reject_internal_actions(actions)

    {{:ok, actions}, %{states: states}}
  end

  # Takes actions received from the upstream elements (closer to source) and performs them on elements from first to last,
  # i.e. in the direction of data flow
  defp pipe_downstream(initial_actions, states) do
    {states, actions} =
      states
      |> Enum.map_reduce(initial_actions, fn {name, module, context, state}, actions ->
        {actions, next_context, next_state} = perform_actions(actions, module, context, state, [])

        {{name, module, next_context, next_state}, actions}
      end)

    {actions, states}
  end

  defp perform_actions([], _module, context, state, next_actions_acc) do
    {next_actions_acc |> Enum.reverse() |> List.flatten(), context, state}
  end

  defp perform_actions([{:forward, data} | actions], module, context, state, next_actions_acc) do
    action =
      case data do
        %Membrane.Buffer{} ->
          {:buffer, {:output, data}}

        [%Membrane.Buffer{} | _tail] ->
          {:buffer, {:output, data}}

        :end_of_stream ->
          {:end_of_stream, :output}

        %_struct{} ->
          if Membrane.Event.event?(data),
            do: {:event, {:output, data}},
            else: {:caps, {:output, data}}
      end

    perform_actions([action | actions], module, context, state, next_actions_acc)
  end

  defp perform_actions([action | actions], module, context, state, next_actions_acc) do
    context = Context.before_incoming_action(context, action)
    result = perform_action(action, module, context, state)
    context = Context.after_incoming_action(context, action)

    case result do
      # Perform split actions within the same element
      {{:ok, [{:split, _action} | _tail] = next_actions}, next_state} ->
        perform_actions(
          next_actions ++ actions,
          module,
          context,
          next_state,
          next_actions_acc
        )

      {{:ok, next_actions}, next_state} when is_list(next_actions) ->
        next_context = Context.after_out_actions(context, next_actions)

        perform_actions(actions, module, next_context, next_state, [
          next_actions | next_actions_acc
        ])

      {:ok, next_state} ->
        perform_actions(actions, module, context, next_state, next_actions_acc)

      term ->
        raise "Invalid return from callback: #{inspect(term)}"
    end
  end

  defp perform_action({:buffer, {:output, []}}, _module, _context, state) do
    {:ok, state}
  end

  defp perform_action({:buffer, {:output, buffer}}, module, context, state) do
    cb_context = struct!(CallbackContext.Process, context)

    module.handle_process_list(:input, List.wrap(buffer), cb_context, state)
  end

  defp perform_action({:caps, {:output, caps}}, module, context, state) do
    cb_context =
      context
      |> Map.put(:old_caps, context.pads.input.caps)
      |> then(&struct!(CallbackContext.Caps, &1))

    module.handle_caps(:input, caps, cb_context, state)
  end

  defp perform_action({:event, {:output, event}}, module, context, state) do
    cb_context = struct!(CallbackContext.Event, context)

    module.handle_event(:input, event, cb_context, state)
  end

  # Internal, FilterAggregator action used to trigger handle_start_of_stream
  defp perform_action({:start_of_stream, :output}, module, context, state) do
    cb_context = struct!(CallbackContext.StreamManagement, context)

    {{:ok, actions}, new_state} =
      case module.handle_start_of_stream(:input, cb_context, state) do
        {:ok, state} -> {{:ok, []}, state}
        result -> result
      end

    {{:ok, Keyword.put_new(actions, :start_of_stream, :output)}, new_state}
  end

  defp perform_action({:end_of_stream, :output}, module, context, state) do
    cb_context = struct!(CallbackContext.StreamManagement, context)

    module.handle_end_of_stream(:input, cb_context, state)
  end

  defp perform_action({:demand, {:input, _size}}, _module, _context, _state) do
    raise "Demands are not supported by #{inspect(__MODULE__)}"
  end

  defp perform_action({:redemand, :output}, _module, _context, _state) do
    raise "Demands are not supported by #{inspect(__MODULE__)}"
  end

  defp perform_action({:notify, message}, _module, _context, state) do
    # Pass the action downstream
    {{:ok, notify: message}, state}
  end

  # Internal action used to manipulate context after performing an action
  defp perform_action({:merge_context, _ctx_data}, _module, _context, state) do
    {:ok, state}
  end

  defp perform_action({:split, {:handle_process, []}}, _module, _context, state) do
    {:ok, state}
  end

  defp perform_action({:split, {:handle_process, args_lists}}, module, context, state) do
    {{:ok, actions}, {context, state}} =
      args_lists
      |> Bunch.Enum.try_flat_map_reduce({context, state}, fn [:input, buffer],
                                                             {acc_context, acc_state} ->
        acc_context = Context.before_incoming_action(acc_context, {:buffer, {:output, buffer}})
        cb_context = struct!(CallbackContext.Process, acc_context)
        {result, state} = module.handle_process(:input, buffer, cb_context, acc_state)
        acc_context = Context.after_incoming_action(acc_context, {:buffer, {:output, buffer}})

        result =
          case result do
            :ok -> {:ok, []}
            _error -> result
          end

        {result, {acc_context, state}}
      end)

    {{:ok, actions ++ [merge_context: context]}, state}
  end

  # Internal, FilterAggregator actions used to trigger playback state change with a proper callback
  defp perform_action(action, module, context, state)
       when action in [
              :stopped_to_prepared,
              :prepared_to_playing,
              :playing_to_prepared,
              :prepared_to_stopped
            ] do
    perform_playback_change(action, module, context, state)
  end

  defp perform_action({:latency, _latency}, _module, _context, _state) do
    raise "latency action not supported in #{inspect(__MODULE__)}"
  end

  defp perform_playback_change(pseudo_action, module, context, state) do
    callback =
      case pseudo_action do
        :stopped_to_prepared -> :handle_stopped_to_prepared
        :prepared_to_playing -> :handle_prepared_to_playing
        :playing_to_prepared -> :handle_playing_to_prepared
        :prepared_to_stopped -> :handle_prepared_to_stopped
      end

    cb_context = struct!(CallbackContext.PlaybackChange, context)

    {{:ok, actions}, new_state} =
      case apply(module, callback, [cb_context, state]) do
        {:ok, state} -> {{:ok, []}, state}
        result -> result
      end

    {{:ok, actions ++ [pseudo_action]}, new_state}
  end

  defp reject_internal_actions(actions) do
    actions
    |> Enum.reject(fn
      {action, _args} ->
        action in [
          :merge_context,
          :start_of_stream
        ]

      action ->
        action in [
          :stopped_to_prepared,
          :prepared_to_playing,
          :playing_to_prepared,
          :prepared_to_stopped
        ]
    end)
  end
end
