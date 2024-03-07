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
          timestamp_offset: integer(),
          qex: Qex.t(),
          buffers_size: non_neg_integer(),
          buffers_number: non_neg_integer(),
          update_heap_on_buffer?: boolean(),
          paused_demand?: boolean(),
          end_of_stream?: boolean(),
          use_pts?: boolean() | nil,
          last_buffer_timestamp: Membrane.Time.t() | nil
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
          pads_heap: Heap.t(),
          waiting_on_buffer_from: MapSet.t()
        }

  defstruct current_queue_time: Membrane.Time.seconds(0),
            pause_demand_boundary: :infinity,
            metric: Metric.Count,
            pad_queues: %{},
            pads_heap: Heap.max(),
            waiting_on_buffer_from: MapSet.new()

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

  @doc """
  Creates and returnes new #{inspect(__MODULE__)}.

  Accepts `t:options()`.
  """
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
  Makes the queue not return any buffer in `pop_batch/3`, until a buffer or end of stream arrival
  from `pad_ref`.
  """
  @spec wait_on_pad(t(), Pad.ref()) :: t()
  def wait_on_pad(%__MODULE__{} = timestamp_queue, pad_ref) do
    timestamp_queue
    |> Map.update!(:waiting_on_buffer_from, &MapSet.put(&1, pad_ref))
  end

  @doc """
  Pushes a buffer associated with a specified pad to the queue.

  Returns a suggested actions list and the updated queue.

  If amount of buffers associated with specified pad in the queue just exceded
  `pause_demand_boundary`, the suggested actions list contains `t:Action.pause_auto_demand()`
  action, otherwise it is equal an empty list.

  Buffers pushed to the queue must have a non-`nil` `dts` or `pts`.
  """
  @spec push_buffer(t(), Pad.ref(), Buffer.t()) :: {[Action.pause_auto_demand()], t()}
  def push_buffer(_timestamp_queue, pad_ref, %Buffer{dts: nil, pts: nil} = buffer) do
    raise """
    #{inspect(__MODULE__)} accepts only buffers whose dts or pts is not nil, but it received\n#{inspect(buffer, pretty: true)}
    from pad #{inspect(pad_ref)}
    """
  end

  def push_buffer(%__MODULE__{} = timestamp_queue, pad_ref, buffer) do
    buffer_size = timestamp_queue.metric.buffers_size([buffer])

    timestamp_queue
    |> Map.update!(:waiting_on_buffer_from, &MapSet.delete(&1, pad_ref))
    |> push_item(pad_ref, {:buffer, buffer})
    |> get_and_update_in([:pad_queues, pad_ref], fn pad_queue ->
      pad_queue
      |> Map.merge(%{
        buffers_size: pad_queue.buffers_size + buffer_size,
        buffers_number: pad_queue.buffers_number + 1
      })
      |> Map.update!(:timestamp_offset, fn
        nil -> timestamp_queue.current_queue_time - (buffer.dts || buffer.pts)
        valid_offset -> valid_offset
      end)
      |> Map.update!(:use_pts?, fn
        nil -> buffer.dts == nil
        valid_boolean -> valid_boolean
      end)
      |> check_timestamps_consistency!(buffer, pad_ref)
      |> actions_after_pushing_buffer(pad_ref, timestamp_queue.pause_demand_boundary)
    end)
  end

  defp check_timestamps_consistency!(pad_queue, buffer, pad_ref) do
    if not pad_queue.use_pts? and buffer.dts == nil do
      raise """
      Buffer #{inspect(buffer, pretty: true)} from pad #{inspect(pad_ref)} has nil dts, while \
      the first buffer from this pad had valid integer there. If the first buffer from a pad has \
      dts different from nil, all later buffers from this pad must meet this property.
      """
    end

    buffer_timestamp = if pad_queue.use_pts?, do: buffer.pts, else: buffer.dts
    last_timestamp = pad_queue.last_buffer_timestamp

    if is_integer(last_timestamp) and last_timestamp > buffer_timestamp do
      raise """
      Buffer #{inspect(buffer, pretty: true)} from pad #{inspect(pad_ref)} has timestamp equal \
      #{inspect(buffer_timestamp)}, but previous buffer from this pad had timestamp equal #{inspect(last_timestamp)}. \
      Buffers from a single pad must have non-decreasing timestamps.
      """
    end

    %{pad_queue | last_buffer_timestamp: buffer_timestamp}
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
    timestamp_queue
    |> Map.update!(:waiting_on_buffer_from, &MapSet.delete(&1, pad_ref))
    |> push_item(pad_ref, :end_of_stream)
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
    |> put_in([:pad_queues, pad_ref], new_pad_queue())
    |> Map.update!(:pads_heap, &Heap.push(&1, {priority, pad_ref}))
  end

  defp new_pad_queue() do
    %{
      timestamp_offset: nil,
      qex: Qex.new(),
      buffers_size: 0,
      buffers_number: 0,
      update_heap_on_buffer?: true,
      paused_demand?: false,
      end_of_stream?: false,
      use_pts?: nil,
      last_buffer_timestamp: nil
    }
  end

  defp actions_after_pushing_buffer(pad_queue, pad_ref, pause_demand_boundary) do
    if not pad_queue.paused_demand? and pad_queue.buffers_size >= pause_demand_boundary do
      {[pause_auto_demand: pad_ref], %{pad_queue | paused_demand?: true}}
    else
      {[], pad_queue}
    end
  end

  defp buffer_time(%Buffer{dts: dts}, %{use_pts?: false, timestamp_offset: timestamp_offset}),
    do: dts + timestamp_offset

  defp buffer_time(%Buffer{pts: pts}, %{use_pts?: true, timestamp_offset: timestamp_offset}),
    do: pts + timestamp_offset

  @type item ::
          {:stream_format, StreamFormat.t()}
          | {:buffer, Buffer.t()}
          | {:event, Event.t()}
          | :end_of_stream

  @type popped_value :: {Pad.ref(), item()}

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

  @spec do_pop(t()) :: {popped_value() | :none, t()}
  defp do_pop(timestamp_queue) do
    if MapSet.size(timestamp_queue.waiting_on_buffer_from) == 0 do
      case Heap.root(timestamp_queue.pads_heap) do
        {_priority, pad_ref} -> do_pop(timestamp_queue, pad_ref)
        nil -> {:none, timestamp_queue}
      end
    else
      case Heap.root(timestamp_queue.pads_heap) do
        # priority :infinity cannot be associated with a buffer
        {:infinity, pad_ref} -> do_pop(timestamp_queue, pad_ref)
        _other -> {:none, timestamp_queue}
      end
    end
  end

  @spec do_pop(t(), Pad.ref()) :: {popped_value() | :none, t()}
  defp do_pop(timestamp_queue, pad_ref) do
    pad_queue = Map.get(timestamp_queue.pad_queues, pad_ref)

    case Qex.pop(pad_queue.qex) do
      {{:value, {:buffer, buffer}}, qex} ->
        buffer_time = buffer_time(buffer, pad_queue)

        case pad_queue do
          %{update_heap_on_buffer?: true} ->
            timestamp_queue
            |> Map.update!(:pads_heap, &(&1 |> Heap.pop() |> Heap.push({-buffer_time, pad_ref})))
            |> put_in([:pad_queues, pad_ref, :update_heap_on_buffer?], false)
            |> do_pop()

          %{buffers_number: 1, end_of_stream?: false} ->
            # last buffer on pad queue without end of stream
            {:none, timestamp_queue}

          pad_queue ->
            buffer_size = timestamp_queue.metric.buffers_size([buffer])

            pad_queue = %{
              pad_queue
              | qex: qex,
                buffers_size: pad_queue.buffers_size - buffer_size,
                buffers_number: pad_queue.buffers_number - 1,
                update_heap_on_buffer?: true
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
