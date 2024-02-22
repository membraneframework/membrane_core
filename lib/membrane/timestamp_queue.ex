defmodule Membrane.TimestampQueue do
  @moduledoc """
  """

  alias Membrane.{Buffer, Event, Pad, StreamFormat}
  alias Membrane.Buffer.Metric
  alias Membrane.Element.Action

  @type buffer_entry :: {:buffer, Buffer.t(), buffer_time :: Membrane.Time.t()}
  @type stream_format_entry :: {:stream_format, StreamFormat.t()}
  @type event_entry :: {:event, Event.t()}

  @type queue_entry :: buffer_entry() | stream_format_entry() | event_entry()

  @type pad_queue :: %{
          pad_ref: Pad.ref(),
          dts_offset: integer(),
          qex: Qex.t(),
          buffers_size: non_neg_integer(),
          paused_demand?: boolean(),
          end_of_stream?: boolean()
        }

  @type t :: %__MODULE__{
          current_queue_time: Membrane.Time.t(),
          pause_demand_boundary: pos_integer() | :infinity,
          metric: Metric.ByteSize | Metric.Count,
          pad_queues: %{optional(Pad.ref()) => pad_queue()},
          pads_heap: Heap.t()
        }

  defstruct current_queue_time: Membrane.Time.seconds(0),
            pause_demand_boundary: :infinity,
            metric: Metric.Count,
            pad_queues: %{},
            pads_heap: Heap.min()

  @type option ::
          {:pause_demand_boundary, pos_integer() | :infinity}
          | {:pause_demand_boundary_unit, :buffers | :bytes}
  @type options :: [option]

  @spec new(options) :: t()
  def new(options \\ []) do
    {unit, options} = Keyword.pop(options, :pause_demand_boundary_unit, :buffers)
    options = [metric: Metric.from_unit(unit)] ++ options

    struct!(__MODULE__, options)
  end

  @type suggested_action :: Action.pause_auto_demand() | Action.resume_auto_demand()
  @type suggested_actions :: [suggested_action()]

  @spec push_buffer(t(), Pad.ref(), Buffer.t()) :: {suggested_actions(), t()}
  def push_buffer(%__MODULE__{} = timestamp_queue, pad_ref, buffer) do
    buffer_size = timestamp_queue.metric.buffers_size([buffer])

    timestamp_queue
    |> push_item(pad_ref, {:buffer, buffer})
    |> get_and_update_in([:pad_queues, pad_ref], fn pad_queue ->
      pad_queue
      |> Map.update!(:buffers_size, &(&1 + buffer_size))
      |> Map.update!(:dts_offset, fn
        nil -> timestamp_queue.current_queue_time - buffer.dts
        valid_offset -> valid_offset
      end)
      |> actions_after_pushing_buffer(timestamp_queue.pause_demand_boundary)
    end)
  end

  @spec push_stream_format(t(), Pad.ref(), StreamFormat.t()) :: t()
  def push_stream_format(%__MODULE__{} = timestamp_queue, pad_ref, stream_format) do
    push_item(timestamp_queue, pad_ref, {:stream_format, stream_format})
  end

  @spec push_event(t(), Pad.ref(), Event.t()) :: t()
  def push_event(%__MODULE__{} = timestamp_queue, pad_ref, event) do
    push_item(timestamp_queue, pad_ref, {:event, event})
  end

  @spec push_end_of_stream(t(), Pad.ref()) :: t()
  def push_end_of_stream(%__MODULE__{} = timestamp_queue, pad_ref) do
    push_item(timestamp_queue, pad_ref, :end_of_stream)
  end

  defp push_item(%__MODULE__{} = timestamp_queue, pad_ref, item) do
    timestamp_queue
    |> maybe_handle_item_from_new_pad(item, pad_ref)
    |> update_in(
      [:pads_queue, pad_ref, :qex],
      &Qex.push(&1, item)
    )
  end

  defp maybe_handle_item_from_new_pad(
         %__MODULE__{pad_queues: pad_queues} = timestamp_queue,
         _item,
         pad_ref
       )
       when is_map_key(pad_queues, pad_ref) do
    timestamp_queue
  end

  defp maybe_handle_item_from_new_pad(%__MODULE__{} = timestamp_queue, first_item, pad_ref) do
    priority =
      case first_item do
        {:buffer, %Buffer{dts: dts}} -> -get_buffer_time(dts, timestamp_queue.current_queue_time)
        _other -> :infinity
      end

    timestamp_queue
    |> put_in([:pad_queues, pad_ref], new_pad_queue(pad_ref))
    |> Map.update!(:pads_heap, &Heap.push(&1, {priority, pad_ref}))
  end

  defp new_pad_queue(pad_ref) do
    %{
      pad_ref: pad_ref,
      dts_offset: nil,
      qex: Qex.new(),
      buffers_size: 0,
      paused_demand?: false,
      end_of_stream?: false
    }
  end

  defp actions_after_pushing_buffer(pad_queue, pause_demand_boundary) do
    if not pad_queue.paused_demand? and pad_queue.buffers_size >= pause_demand_boundary do
      {[pause_auto_demand: pad_queue.pad_ref], %{pad_queue | paused_demand?: true}}
    else
      {[], pad_queue}
    end
  end

  defp get_buffer_time(buffer_dts, dts_offset), do: buffer_dts + dts_offset

  @type item ::
          {:stream_format, StreamFormat.t()}
          | {:buffer, Buffer.t()}
          | {:event, Event.t()}
          | :end_of_stream

  @type popped_value :: {Pad.ref(), item()}

  @spec pop(t()) :: {suggested_actions(), popped_value() | :none, t()}
  def pop(%__MODULE__{} = timestamp_queue) do
    {value, timestamp_queue} = do_pop(timestamp_queue)

    case value do
      {pad_ref, {:buffer, _buffer}} ->
        {actions, timestamp_queue} = actions_after_popping_buffer(timestamp_queue, pad_ref)
        {actions, value, timestamp_queue}

      value ->
        {[], value, timestamp_queue}
    end
  end

  @spec do_pop(t()) :: {popped_value() | :none, t()}
  defp do_pop(timestamp_queue) do
    case Heap.root(timestamp_queue.pads_heap) do
      {priority, pad_ref} -> do_pop(timestamp_queue, pad_ref, priority)
      nil -> {:none, timestamp_queue}
    end
  end

  defp do_pop(timestamp_queue, pad_ref, pad_priority) do
    pad_queue = Map.get(timestamp_queue.pad_queues, pad_ref)

    case Qex.pop(pad_queue.qex) do
      {{:value, {:buffer, buffer}}, qex} ->
        buffer_time = get_buffer_time(buffer.dts, pad_queue.dts_offset)
        buffer_size = timestamp_queue.metric.buffers_size([buffer])

        cond do
          buffer_time != -pad_priority ->
            timestamp_queue
            |> Map.update!(:pads_heap, &(&1 |> Heap.pop() |> Heap.push({-buffer_time, pad_ref})))
            |> do_pop()

          buffer_size == pad_queue.buffers_size and not pad_queue.end_of_stream? ->
            # last buffer on pad queue without end of stream
            {:none, timestamp_queue}

          true ->
            # this must be recursive call of pop()

            pad_queue = %{
              pad_queue
              | qex: qex,
                buffers_size: pad_queue.buffers_size - buffer_size
            }

            timestamp_queue = timestamp_queue |> put_in([:pad_queues, pad_ref], pad_queue)

            {{pad_ref, {:buffer, buffer}}, timestamp_queue}
        end

      {{:value, item}, qex} ->
        timestamp_queue =
          timestamp_queue
          |> put_in([:pad_queues, pad_ref, :qex], qex)

        {{pad_ref, item}, timestamp_queue}

      {:empty, _qex} ->
        timestamp_queue
        |> Map.update!(:pad_queues, &Map.delete(&1, pad_ref))
        |> Map.update!(:pads_heap, &Heap.pop/1)
        |> do_pop()
    end
  end

  @spec pop_batch(t()) :: {suggested_actions(), [popped_value() | :none], t()}
  def pop_batch(%__MODULE__{} = timestamp_queue) do
    {batch, timestamp_queue} = do_pop_batch(timestamp_queue)

    {actions, timestamp_queue} =
      batch
      |> Enum.reduce(MapSet.new(), fn
        {pad_ref, {:buffer, _buffer}}, map_set -> MapSet.put(map_set, pad_ref)
        _other, map_set -> map_set
      end)
      |> Enum.reduce({[], timestamp_queue}, fn pad_ref, {actions_acc, timestamp_queue} ->
        {actions, timestamp_queue} = actions_after_popping_buffer(timestamp_queue, pad_ref)
        {actions ++ actions_acc, timestamp_queue}
      end)

    {actions, batch, timestamp_queue}
  end

  @spec do_pop_batch(t(), [popped_value()]) :: {[popped_value() | :none], t()}
  defp do_pop_batch(timestamp_queue, acc \\ []) do
    case do_pop(timestamp_queue) do
      {:none, timestamp_queue} -> {Enum.reverse(acc), timestamp_queue}
      {value, timestamp_queue} -> do_pop_batch(timestamp_queue, [value | acc])
    end
  end

  defp actions_after_popping_buffer(
         %__MODULE__{pause_demand_boundary: boundary} = timestamp_queue,
         pad_ref
       ) do
    pad_queue = get_in(timestamp_queue, [:pad_queues, pad_ref])

    if pad_queue.demand_paused? and pad_queue.buffers_size < boundary do
      timestamp_queue =
        timestamp_queue
        |> put_in([:pad_queues, pad_ref, :demand_paused?], false)

      {[resume_auto_demand: pad_ref], timestamp_queue}
    else
      {[], timestamp_queue}
    end
  end
end
