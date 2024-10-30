defmodule Membrane.ForwardingFilter do
  use Membrane.Filter

  def_input_pad :input,
    accepted_format: _any,
    availability: :on_request,
    max_instances: 1

  def_output_pad :output,
    accepted_format: _any,
    availability: :on_request,
    max_instances: 1

  def_options notify_on_stream_format?: [default: false], notify_on_event?: [default: false]

  defguardp flowing?(ctx, state)
            when ctx.playback == :playing and state.input != nil and state.output != nil

  @impl true
  def handle_init(_ctx, opts) do
    state =
      opts
      |> Map.from_struct()
      |> Map.merge(%{input: nil, output: nil, queue: []})

    {[], state}
  end

  @impl true
  def handle_pad_added(Pad.ref(direction, _ref) = pad, ctx, state) do
    state = state |> Map.put(direction, pad)
    flush_queue_if_flowing(ctx, state)
  end

  @impl true
  def handle_playing(ctx, state), do: flush_queue_if_flowing(ctx, state)

  [handle_buffer: :buffer, handle_event: :event, handle_stream_format: :stream_format]
  |> Enum.map(fn {callback, action} ->
    @impl true
    def unquote(callback)(pad, item, ctx, state) when flowing?(ctx, state) do
      actions = [{unquote(action), {opposite_pad(pad, state), item}}]
      actions = actions ++ maybe_notify_parent(unquote(action), pad, item, state)
      {actions, state}
    end

    @impl true
    def unquote(callback)(pad, item, _ctx, state) do
      state = unquote(action) |> store_in_queue(pad, item, state)
      actions = unquote(action) |> maybe_notify_parent(pad, item, state)
      {actions, state}
    end
  end)

  @impl true
  def handle_end_of_stream(pad, ctx, state) when flowing?(ctx, state) do
    {[end_of_stream: opposite_pad(pad, state)], state}
  end

  @impl true
  def handle_end_of_stream(pad, _ctx, state) do
    {[], store_in_queue(:end_of_stream, pad, nil, state)}
  end

  defp store_in_queue(action, pad, item, state) do
    state |> Map.update!(:queue, &[{action, pad, item} | &1])
  end

  defp flush_queue_if_flowing(ctx, state) do
    if flowing?(ctx, state), do: flush_queue(ctx, state), else: {[], state}
  end

  defp flush_queue(ctx, state) when flowing?(ctx, state) do
    actions =
      state.queue
      |> Enum.reverse()
      |> Enum.map(fn
        {:end_of_stream, _input, nil} -> {:end_of_stream, state.output}
        {action, pad, item} -> {action, {opposite_pad(pad, state), item}}
      end)

    {actions, %{state | queue: nil}}
  end

  defp opposite_pad(Pad.ref(:input, _ref), state), do: state.output
  defp opposite_pad(Pad.ref(:output, _ref), state), do: state.input

  defp maybe_notify_parent(:event, pad, event, %{notify_on_event?: true}),
    do: [notiy_parent: {:event, pad, event}]

  defp maybe_notify_parent(:stream_format, pad, format, %{notify_on_stream_format?: true}),
    do: [notiy_parent: {:stream_format, pad, format}]

  defp maybe_notify_parent(_type, _pad, _item, _state), do: []
end
