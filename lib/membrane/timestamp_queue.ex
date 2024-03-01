defmodule Membrane.TimestampQueue do
  @moduledoc """
  Implementation of a queue, that accepts:
   - Membrane buffers
   - events
   - stream formats
   - end of streams
  from various pads. Items in queue are sorted according to their timestamps.

  Moreover, #{inspect(__MODULE__)} is able to manage demand of pads, based on the amount of buffers
  from each pad currently stored in the queue.
  """

  use Bunch.Access

  alias Membrane.{Buffer, Event, Pad, StreamFormat}
  alias Membrane.Buffer.Metric
  alias Membrane.Element.Action

  @type pad_queue :: %{
          pad_ref: Pad.ref(),
          dts_offset: integer(),
          qex: Qex.t(),
          buffers_size: non_neg_integer(),
          paused_demand?: boolean(),
          end_of_stream?: boolean()
        }

  @typedoc """
  A queue, that accepts buffers, stream formats and events from various pads and sorts them based on
  their timestamps.
  """
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
            pads_heap: Heap.max()

  @typedoc """
  Options passed to #{inspect(__MODULE__)}.new/1.

  Following options are allowed:
    - `:pause_demand_boundary` - positive integer or `:infinity` (default to `:infinity`). Tells, what
      amount of buffers associated with specific pad must be stored in the queue, to pause auto demand.
    - `:pause_demand_boundary_unit` - `:buffers` or `:bytes` (deafult to `:buffers`). Tells, in which metric
      `:pause_demand_boundary` is specified.
  """
  @type options :: [
          pause_demand_boundary: pos_integer() | :infinity,
          pause_demand_boundary_unit: :buffers | :bytes
        ]

  @spec new(options) :: t()
  def new(options \\ []) do
    metric =
      options
      |> Keyword.get(:pause_demand_boundary_unit, :buffers)
      |> Metric.from_unit()

    %__MODULE__{
      metric: metric,
      pause_demand_boundary: Keyword.get(options, :pause_demand_boundary, :infinity)
    }
  end

  @doc """
  Pushes a buffer associated with a specified pad to the queue.

  Returns a suggested actions list and the updated queue.

  If amount of buffers associated with specified pad in the queue just exceded
  `pause_demand_boundary`, the suggested actions list contains `t:Action.pause_auto_demand()`
  action, otherwise it is equal an empty list.

  Buffers pushed to the queue must have non-`nil` `dts`.
  """
  @spec push_buffer(t(), Pad.ref(), Buffer.t()) :: {[Action.pause_auto_demand()], t()}
  def push_buffer(_timestamp_queue, pad_ref, %Buffer{dts: nil} = buffer) do
    raise """
    #{inspect(__MODULE__)} accepts only buffers whose dts is not nil, but it received\n#{inspect(buffer, pretty: true)}
    from pad #{inspect(pad_ref)}
    """
  end

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

  @doc """
  Pushes stream format associated with a specified pad to the queue.

  Returns the updated queue.
  """
  @spec push_stream_format(t(), Pad.ref(), StreamFormat.t()) :: t()
  def push_stream_format(%__MODULE__{} = timestamp_queue, pad_ref, stream_format) do
    push_item(timestamp_queue, pad_ref, {:stream_format, stream_format})
  end

  @doc """
  Pushes event associated with a specified pad to the queue.

  Returns the updated queue.
  """
  @spec push_event(t(), Pad.ref(), Event.t()) :: t()
  def push_event(%__MODULE__{} = timestamp_queue, pad_ref, event) do
    push_item(timestamp_queue, pad_ref, {:event, event})
  end

  @doc """
  Pushes end of stream of the specified pad to the queue.

  Returns the updated queue.
  """
  @spec push_end_of_stream(t(), Pad.ref()) :: t()
  def push_end_of_stream(%__MODULE__{} = timestamp_queue, pad_ref) do
    push_item(timestamp_queue, pad_ref, :end_of_stream)
    |> put_in([:pad_queues, pad_ref, :end_of_stream?], true)
  end

  defp push_item(%__MODULE__{} = timestamp_queue, pad_ref, item) do
    timestamp_queue
    |> maybe_handle_item_from_new_pad(item, pad_ref)
    |> update_in(
      [:pad_queues, pad_ref, :qex],
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
        {:buffer, _buffer} -> -timestamp_queue.current_queue_time
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

  @doc """
  Pops up to 1 buffer from the queue.

  Returns a suggested actions list, popped buffer and the updated queue.

  If amount of buffers from pad associated with popped buffer just dropped below
  `pause_demand_boundary`, the suggested actions list contains `t:Action.resume_auto_demand()`
  action, otherwise it is an empty list.

  If the queue cannot return any buffer, returns `:none` in it's place instead. Note, that
  the queue doesn't have to be empty to be unable to return a buffer - sometimes queue has to
  keep up to 1 buffer for each pad, to be able to work correctly.
  """
  @spec pop(t()) :: {[Action.resume_auto_demand()], popped_value() | :none, t()}
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
          pad_priority != -buffer_time ->
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

            timestamp_queue =
              timestamp_queue
              |> Map.put(:current_queue_time, buffer_time)
              |> put_in([:pad_queues, pad_ref], pad_queue)

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

  @doc """
  Pops as many buffers from the queue, as it is possible.

  Returns suggested actions list, list of popped buffers and the updated queue.

  If the amount of buffers associated with any pad in the queue falls below the
  `pause_demand_boundary`, the suggested actions list contains `t:Action.resume_auto_demand()`
  actions, otherwise it is an empty list.

  If the queue cannot return any buffer, empty list is returned. Note, that queue doesn't have to be
  empty to be unable to return a buffer - sometimes queue must keep up to 1 buffer for each pad,
  to be able to work correctly.
  """
  @spec pop_batch(t()) :: {[Action.resume_auto_demand()], [popped_value() | :none], t()}
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
    with %{paused_demand?: true, buffers_size: size} when size < boundary <-
           get_in(timestamp_queue, [:pad_queues, pad_ref]) do
      timestamp_queue =
        timestamp_queue
        |> put_in([:pad_queues, pad_ref, :paused_demand?], false)

      {[resume_auto_demand: pad_ref], timestamp_queue}
    else
      _other -> {[], timestamp_queue}
    end
  end
end
