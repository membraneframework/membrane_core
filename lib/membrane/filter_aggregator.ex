defmodule Membrane.FilterAggregator do
  @moduledoc """
  An element allowing to aggregate many filters within one Elixir process.

  Warning: This element is still in experimental phase

  This element supports only filters with one input and one output
  with following restrictions:
  * not using timers
  * not relying on received messages
  * not expecting any events coming from downstream elements
  * their pads have to be named `:input` and `:output`
  * their pads cannot use manual demands
  * the first filter must make demands in buffers
  """
  use Membrane.Filter

  alias Membrane.Core.FilterAggregator.Context
  alias Membrane.Element.CallbackContext

  require Membrane.Core.FilterAggregator.InternalAction, as: InternalAction
  require Membrane.Logger

  def_options filters: [
                spec: [{Membrane.Child.name_t(), module() | struct()}],
                description: "A list of filters applied to incoming stream"
              ]

  def_input_pad :input,
    accepted_format: _any,
    demand_mode: :auto

  def_output_pad :output,
    demand_mode: :auto,
    accepted_format: _any

  @impl true
  def handle_init(agg_ctx, %__MODULE__{filters: filter_specs}) do
    if filter_specs == [] do
      Membrane.Logger.warn("No filters provided, #{inspect(__MODULE__)} will be a no-op")
    end

    states =
      filter_specs
      |> Enum.map(fn
        {name, %module{} = options} ->
          {name, module, options}

        {name, module} ->
          unless is_atom(module) and Membrane.Element.element?(module) do
            raise ArgumentError, """
            The module "#{inspect(module)}" is not a Membrane Element.
            Make sure that given module is the right one, implements proper behaviour
            and all needed dependencies are properly specified in the Mixfile.
            """
          end

          options =
            module
            |> Code.ensure_loaded!()
            |> function_exported?(:__struct__, 1)
            |> case do
              true -> struct!(module, [])
              false -> %{}
            end

          {name, module, options}

        invalid_spec ->
          raise ArgumentError, "Invalid filter spec: `#{inspect(invalid_spec)}`"
      end)
      |> Enum.map(fn {name, module, options} ->
        context = Context.build_context!(name, module, agg_ctx)
        {[], state} = module.handle_init(context, options)
        {name, module, context, state}
      end)

    {[], %{states: states}}
  end

  @impl true
  def handle_setup(_ctx, %{states: states}) do
    {actions, states} = pipe_downstream([InternalAction.setup()], states)
    actions = reject_internal_actions(actions)
    {actions, %{states: states}}
  end

  @impl true
  def handle_playing(agg_ctx, %{states: states}) do
    contexts = states |> Enum.map(fn {_name, _module, context, _state} -> context end)
    prev_contexts = contexts |> List.insert_at(-1, agg_ctx)
    next_contexts = [agg_ctx | contexts]

    states =
      [prev_contexts, states, next_contexts]
      |> Enum.zip_with(fn [prev_context, {name, module, context, state}, next_context] ->
        context = Context.link_contexts(context, prev_context, next_context)
        {name, module, context, state}
      end)

    {actions, states} = pipe_downstream([InternalAction.playing()], states)
    actions = reject_internal_actions(actions)
    {actions, %{states: states}}
  end

  @impl true
  def handle_start_of_stream(:input, _ctx, %{states: states}) do
    {actions, states} = pipe_downstream([InternalAction.start_of_stream(:output)], states)
    actions = reject_internal_actions(actions)

    {actions, %{states: states}}
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, %{states: states}) do
    {actions, states} = pipe_downstream([end_of_stream: :output], states)
    actions = reject_internal_actions(actions)

    {actions, %{states: states}}
  end

  @impl true
  def handle_event(:input, event, _ctx, %{states: states}) do
    {actions, states} = pipe_downstream([event: {:output, event}], states)
    actions = reject_internal_actions(actions)

    {actions, %{states: states}}
  end

  @impl true
  def handle_stream_format(:input, stream_format, _ctx, %{states: states}) do
    {actions, states} = pipe_downstream([stream_format: {:output, stream_format}], states)
    actions = reject_internal_actions(actions)
    {actions, %{states: states}}
  end

  @impl true
  def handle_process_list(:input, buffers, _ctx, %{states: states}) do
    {actions, states} = pipe_downstream([buffer: {:output, buffers}], states)
    actions = reject_internal_actions(actions)

    {actions, %{states: states}}
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

  defp perform_actions([action | actions], module, context, state, next_actions_acc) do
    context = Context.before_incoming_action(context, action)
    result = perform_action(action, module, context, state)
    context = Context.after_incoming_action(context, action)

    case result do
      # Perform split actions within the same element
      {[{:split, _action} | _tail] = next_actions, next_state} ->
        perform_actions(
          next_actions ++ actions,
          module,
          context,
          next_state,
          next_actions_acc
        )

      {next_actions, next_state} when is_list(next_actions) ->
        next_actions = transform_out_actions(next_actions)
        next_context = Context.after_out_actions(context, next_actions)

        perform_actions(actions, module, next_context, next_state, [
          next_actions | next_actions_acc
        ])

      {[], next_state} ->
        perform_actions(actions, module, context, next_state, next_actions_acc)

      term ->
        raise "Invalid return from callback: #{inspect(term)}"
    end
  end

  defp perform_action({:buffer, {:output, []}}, _module, _context, state) do
    {[], state}
  end

  defp perform_action({:buffer, {:output, buffer}}, module, context, state) do
    cb_context = struct!(CallbackContext.Process, context)
    module.handle_process_list(:input, List.wrap(buffer), cb_context, state)
  end

  defp perform_action({:stream_format, {:output, stream_format}}, module, context, state) do
    cb_context =
      context
      |> Map.put(:old_stream_format, context.pads.input.stream_format)
      |> then(&struct!(CallbackContext.StreamFormat, &1))

    module.handle_stream_format(:input, stream_format, cb_context, state)
  end

  defp perform_action({:event, {:output, event}}, module, context, state) do
    cb_context = struct!(CallbackContext.Event, context)
    module.handle_event(:input, event, cb_context, state)
  end

  # Internal, FilterAggregator action used to trigger handle_start_of_stream
  defp perform_action(InternalAction.start_of_stream(:output), module, context, state) do
    cb_context = struct!(CallbackContext.StreamManagement, context)

    {actions, new_state} = module.handle_start_of_stream(:input, cb_context, state)

    {[InternalAction.start_of_stream(:output) | actions], new_state}
  end

  defp perform_action({:end_of_stream, :output}, module, context, state) do
    cb_context = struct!(CallbackContext.StreamManagement, context)
    module.handle_end_of_stream(:input, cb_context, state)
  end

  defp perform_action({:demand, {:input, _size}}, _module, _context, _state) do
    raise "Manual demands are not supported by #{inspect(__MODULE__)}"
  end

  defp perform_action({:redemand, :output}, _module, _context, _state) do
    raise "Demands are not supported by #{inspect(__MODULE__)}"
  end

  defp perform_action({:notify, message}, _module, _context, state) do
    # Pass the action downstream
    {[notify: message], state}
  end

  # Internal action used to manipulate context after performing an action
  defp perform_action(InternalAction.merge_context(_ctx_data), _module, _context, state) do
    {[], state}
  end

  defp perform_action({:split, {:handle_process, []}}, _module, _context, state) do
    {[], state}
  end

  defp perform_action({:split, {:handle_process, args_lists}}, module, context, state) do
    {actions, {context, state}} =
      args_lists
      |> Enum.flat_map_reduce({context, state}, fn [:input, buffer], {acc_context, acc_state} ->
        acc_context = Context.before_incoming_action(acc_context, {:buffer, {:output, buffer}})
        cb_context = struct!(CallbackContext.Process, acc_context)

        {actions, state} = module.handle_process(:input, buffer, cb_context, acc_state)

        acc_context = Context.after_incoming_action(acc_context, {:buffer, {:output, buffer}})

        {actions, {acc_context, state}}
      end)

    {actions ++ [InternalAction.merge_context(context)], state}
  end

  defp perform_action(InternalAction.setup(), module, context, state) do
    cb_context = struct!(CallbackContext.Setup, context)
    {actions, state} = module.handle_setup(cb_context, state)
    {actions ++ [InternalAction.setup()], state}
  end

  defp perform_action(InternalAction.playing(), module, context, state) do
    cb_context = struct!(CallbackContext.Playing, context)
    {actions, state} = module.handle_playing(cb_context, state)
    {actions ++ [InternalAction.playing()], state}
  end

  defp perform_action({:latency, _latency}, _module, _context, _state) do
    raise "latency action not supported in #{inspect(__MODULE__)}"
  end

  defp reject_internal_actions(actions) do
    actions
    |> Enum.reject(&InternalAction.is_internal_action/1)
  end

  defp transform_out_actions(actions) do
    actions
    |> Enum.map(fn
      {:forward, data} -> resolve_forward_action(data)
      action -> action
    end)
  end

  defp resolve_forward_action(%Membrane.Buffer{} = buffer) do
    {:buffer, {:output, buffer}}
  end

  defp resolve_forward_action([%Membrane.Buffer{} | _tail] = buffers) do
    {:buffer, {:output, buffers}}
  end

  defp resolve_forward_action(:end_of_stream) do
    {:end_of_stream, :output}
  end

  defp resolve_forward_action(%_struct{} = data) do
    if Membrane.Event.event?(data),
      do: {:event, {:output, data}},
      else: {:stream_format, {:output, data}}
  end
end
