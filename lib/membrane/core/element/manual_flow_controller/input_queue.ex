defmodule Membrane.Core.Element.ManualFlowController.InputQueue do
  @moduledoc false
  # Queue that is attached to the `:input` pad when working in a `:manual` flow control mode.

  # It stores `Membrane.Buffer`, `Membrane.Event` and `Membrane.StreamFormat` structs and
  # prevents the situation where the data in a stream contains the discontinuities.
  # It also guarantees that element won't be flooded with the incoming data.

  use Bunch

  alias Membrane.Buffer
  alias Membrane.Core.Element.AtomicDemand
  alias Membrane.Core.Telemetry
  alias Membrane.Event
  alias Membrane.Pad
  alias Membrane.StreamFormat

  require Membrane.Core.Stalker, as: Stalker
  require Membrane.Logger

  @qe Qex

  @non_buf_types [:event, :stream_format]

  @type output_value ::
          {:event | :stream_format, any} | {:buffers, list, pos_integer, pos_integer}
  @type output :: {:empty | :value, [output_value]}

  @type queue_item() :: Buffer.t() | Event.t() | StreamFormat.t() | atom()

  @type t :: %__MODULE__{
          q: @qe.t(),
          log_tag: String.t(),
          target_size: pos_integer(),
          size: non_neg_integer(),
          demand: non_neg_integer(),
          inbound_metric: module(),
          outbound_metric: module(),
          pad_ref: Pad.ref(),
          atomic_demand: AtomicDemand.t(),
          stalker_metrics: %{atom() => any()},
          last_outbound_buffer: Buffer.t() | nil,
          first_outbound_buffer: Buffer.t() | nil
        }

  @enforce_keys [
    :q,
    :log_tag,
    :target_size,
    :atomic_demand,
    :inbound_metric,
    :outbound_metric,
    :pad_ref,
    :stalker_metrics
  ]

  defstruct @enforce_keys ++ [:last_outbound_buffer, :first_outbound_buffer, size: 0, demand: 0]

  @default_target_size_factor 100

  @spec default_min_demand_factor() :: number()
  def default_min_demand_factor, do: 0.25

  @spec new(%{
          inbound_demand_unit: Buffer.Metric.unit(),
          outbound_demand_unit: Buffer.Metric.unit(),
          atomic_demand: AtomicDemand.t(),
          pad_ref: Pad.ref(),
          log_tag: String.t(),
          target_size: pos_integer() | nil
        }) :: t()
  def new(config) do
    %{
      inbound_demand_unit: inbound_demand_unit,
      outbound_demand_unit: outbound_demand_unit,
      atomic_demand: atomic_demand,
      pad_ref: pad_ref,
      log_tag: log_tag,
      target_size: target_size
    } = config

    inbound_metric = Buffer.Metric.from_unit(inbound_demand_unit)
    outbound_metric = Buffer.Metric.from_unit(outbound_demand_unit)

    default_target_size = inbound_metric.buffer_size_approximation() * @default_target_size_factor

    target_size = target_size || default_target_size

    size_metric = :atomics.new(1, [])

    Stalker.register_metric_function(
      :input_queue_size,
      fn -> :atomics.get(size_metric, 1) end,
      pad: pad_ref
    )

    %__MODULE__{
      q: @qe.new(),
      log_tag: log_tag,
      target_size: target_size,
      inbound_metric: inbound_metric,
      outbound_metric: outbound_metric,
      atomic_demand: atomic_demand,
      pad_ref: pad_ref,
      stalker_metrics: %{size: size_metric}
    }
    |> maybe_increase_atomic_demand()
  end

  @spec store(t(), :buffer | :buffers | :event | :stream_format, queue_item() | [queue_item()]) ::
          t()
  def store(input_queue, type \\ :buffers, v)

  def store(input_queue, :buffers, v) when is_list(v) do
    %__MODULE__{size: size, target_size: target_size, stalker_metrics: stalker_metrics} =
      input_queue

    if size >= target_size do
      """
      Received buffers despite not requesting them.
      It is probably caused by overestimating demand by previous element.
      """
      |> mk_log(input_queue)
      |> Membrane.Logger.debug_verbose()
    end

    %__MODULE__{size: size} = input_queue = do_store_buffers(input_queue, v)

    :atomics.put(stalker_metrics.size, 1, size)

    input_queue
  end

  def store(input_queue, :buffer, v), do: store(input_queue, :buffers, [v])

  def store(%__MODULE__{q: q, size: size} = input_queue, type, v)
      when type in @non_buf_types do
    "Storing #{type}" |> mk_log(input_queue) |> Membrane.Logger.debug_verbose()
    Telemetry.report_store(size, input_queue.log_tag)

    %__MODULE__{input_queue | q: q |> @qe.push({:non_buffer, type, v})}
  end

  defp do_store_buffers(
         %__MODULE__{
           q: q,
           size: size,
           demand: demand,
           inbound_metric: inbound_metric,
           outbound_metric: outbound_metric
         } = input_queue,
         v
       ) do
    inbound_metric_buffer_size = size(v, inbound_metric)
    outbound_metric_buffer_size = size(v, outbound_metric)

    "Storing #{inspect(inbound_metric_buffer_size)} buffers"
    |> mk_log(input_queue)
    |> Membrane.Logger.debug_verbose()

    %__MODULE__{
      input_queue
      | q: q |> @qe.push({:buffers, v, inbound_metric_buffer_size, outbound_metric_buffer_size}),
        size: size + inbound_metric_buffer_size,
        demand: demand - inbound_metric_buffer_size
    }
  end

  @spec take(t, non_neg_integer() | Membrane.Time.t()) :: {output(), t}
  def take(%__MODULE__{} = input_queue, demand) do
    "Handling #{inspect(demand)} #{inspect(input_queue.outbound_metric)}"
    |> mk_log(input_queue)
    |> Membrane.Logger.debug_verbose()

    {out, input_queue} = do_take(input_queue, demand)

    input_queue =
      input_queue
      |> maybe_increase_atomic_demand()
      |> update_first_and_last_outbound_buffers(out)

    %{size: size, stalker_metrics: stalker_metrics} = input_queue
    Telemetry.report_take(size, input_queue.log_tag)
    :atomics.put(stalker_metrics.size, 1, size)

    {out, input_queue}
  end

  defp do_take(
         %__MODULE__{
           q: q,
           size: size,
           inbound_metric: inbound_metric,
           outbound_metric: outbound_metric,
           first_outbound_buffer: first_outbound_buffer,
           last_outbound_buffer: last_outbound_buffer
         } = input_queue,
         demand
       ) do
    {out, nq, new_size} =
      q
      |> q_pop(
        demand,
        inbound_metric,
        outbound_metric,
        size,
        first_outbound_buffer,
        last_outbound_buffer,
        []
      )

    input_queue = %{input_queue | q: nq, size: new_size}
    {out, input_queue}
  end

  defp q_pop(
         q,
         size_to_take_in_outbound_metric,
         inbound_metric,
         outbound_metric,
         queue_size,
         first_outbound_buffer,
         last_outbound_buffer,
         acc
       )

  defp q_pop(
         q,
         size_to_take_in_outbound_metric,
         inbound_metric,
         outbound_metric,
         queue_size,
         first_outbound_buffer,
         last_outbound_buffer,
         acc
       )
       when size_to_take_in_outbound_metric > 0 do
    q
    |> @qe.pop
    |> case do
      {{:value, {:buffers, buffers, inbound_metric_buf_size, _outbound_metric_buf_size}}, nq} ->
        {buffers, excess_buffers} =
          outbound_metric.split_buffers(
            buffers,
            size_to_take_in_outbound_metric,
            first_outbound_buffer,
            last_outbound_buffer
          )

        buffers_size_inbound_metric = size(buffers, inbound_metric)
        buffers_size_outbound_metric = size(buffers, outbound_metric)

        new_size_to_take_in_outbound_metric =
          if Buffer.Metric.is_timestamp_metric?(outbound_metric) do
            size_to_take_in_outbound_metric
          else
            size_to_take_in_outbound_metric - buffers_size_outbound_metric
          end

        case excess_buffers do
          [] ->
            q_pop(
              nq,
              new_size_to_take_in_outbound_metric,
              inbound_metric,
              outbound_metric,
              queue_size - inbound_metric_buf_size,
              first_outbound_buffer,
              last_outbound_buffer,
              [
                {:buffers, buffers, buffers_size_inbound_metric, buffers_size_outbound_metric}
                | acc
              ]
            )

          non_empty_excess_buffers ->
            excess_buffers_inbound_metric_size = size(non_empty_excess_buffers, inbound_metric)
            excess_buffers_outbound_metric_size = size(non_empty_excess_buffers, outbound_metric)

            nq =
              @qe.push_front(
                nq,
                {:buffers, excess_buffers, excess_buffers_inbound_metric_size,
                 excess_buffers_outbound_metric_size}
              )

            {{:value,
              [
                {:buffers, buffers, buffers_size_inbound_metric, buffers_size_outbound_metric}
                | acc
              ]
              |> Enum.reverse()}, nq,
             queue_size - inbound_metric_buf_size + excess_buffers_inbound_metric_size}
        end

      {:empty, nq} ->
        {{:empty, acc |> Enum.reverse()}, nq, queue_size}

      {{:value, {:non_buffer, type, e}}, nq} ->
        q_pop(
          nq,
          size_to_take_in_outbound_metric,
          inbound_metric,
          outbound_metric,
          queue_size,
          first_outbound_buffer,
          last_outbound_buffer,
          [
            {type, e} | acc
          ]
        )
    end
  end

  defp q_pop(
         q,
         0,
         inbound_metric,
         outbound_metric,
         queue_size,
         first_outbound_buffer,
         last_outbound_buffer,
         acc
       ) do
    q
    |> @qe.pop
    |> case do
      {{:value, {:non_buffer, type, e}}, nq} ->
        q_pop(
          nq,
          0,
          inbound_metric,
          outbound_metric,
          queue_size,
          first_outbound_buffer,
          last_outbound_buffer,
          [
            {type, e} | acc
          ]
        )

      _empty_or_buffer ->
        {{:value, acc |> Enum.reverse()}, q, queue_size}
    end
  end

  @spec maybe_increase_atomic_demand(t()) :: t()
  defp maybe_increase_atomic_demand(
         %__MODULE__{
           size: size,
           target_size: target_size,
           atomic_demand: atomic_demand,
           demand: demand
         } = input_queue
       )
       when target_size > size + demand do
    diff = max(target_size - size - demand, div(target_size, 2))

    """
    Increasing AtomicDemand for pad  #{inspect(input_queue.pad_ref)} by #{inspect(diff)}
    """
    |> mk_log(input_queue)
    |> Membrane.Logger.debug_verbose()

    :ok = AtomicDemand.increase(atomic_demand, diff)
    %{input_queue | demand: demand + diff}
  end

  defp maybe_increase_atomic_demand(%__MODULE__{} = input_queue), do: input_queue

  defp update_first_and_last_outbound_buffers(input_queue, {_empty_or_value, outputs}) do
    buffers =
      outputs
      |> Enum.flat_map(fn
        {:buffers, buffers, _in_buf_size, _out_buf_size} -> buffers
        _other_output -> []
      end)

    input_queue
    |> Map.update!(:first_outbound_buffer, &(&1 || List.first(buffers)))
    |> Map.update!(:last_outbound_buffer, &(List.last(buffers) || &1))
  end

  # This function may be unused if particular logs are pruned
  @dialyzer {:no_unused, mk_log: 2}
  defp mk_log(message, input_queue) do
    %__MODULE__{
      log_tag: log_tag,
      size: size,
      target_size: target_size
    } = input_queue

    [
      "InputQueue #{log_tag}: ",
      message,
      "\n",
      "InputQueue size: #{inspect(size)}, target size: #{inspect(target_size)}"
    ]
  end

  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{size: size}), do: size == 0

  defp size(buffers, metric) do
    case metric.buffers_size(buffers) do
      {:ok, size} -> size
      {:error, :operation_not_supported} -> nil
    end
  end
end
