defmodule Membrane.Core.Element.InputQueue do
  @moduledoc false
  # Queue that is attached to the `:input` pad when working in a `:manual` flow control mode.

  # It stores `Membrane.Buffer`, `Membrane.Event` and `Membrane.StreamFormat` structs and
  # prevents the situation where the data in a stream contains the discontinuities.
  # It also guarantees that element won't be flooded with the incoming data.

  use Bunch

  alias Membrane.Core.Element.DemandCounter
  alias Membrane.Buffer
  alias Membrane.Core.Telemetry
  alias Membrane.Pad

  require Membrane.Core.Telemetry
  require Membrane.Logger

  @qe Qex

  @non_buf_types [:event, :stream_format]

  @type output_value ::
          {:event | :stream_format, any} | {:buffers, list, pos_integer, pos_integer}
  @type output :: {:empty | :value, [output_value]}

  @type t :: %__MODULE__{
          q: @qe.t(),
          log_tag: String.t(),
          target_size: pos_integer(),
          size: non_neg_integer(),
          demand: integer(),
          min_demand: pos_integer(),
          inbound_metric: module(),
          outbound_metric: module()
        }

  @enforce_keys [
    :q,
    :log_tag,
    :target_size,
    :size,
    :demand,
    :demand_counter,
    :min_demand,
    :inbound_metric,
    :outbound_metric
  ]

  defstruct @enforce_keys

  @default_target_size_factor 40

  @spec default_min_demand_factor() :: number()
  def default_min_demand_factor, do: 0.25

  @spec init(%{
          inbound_demand_unit: Buffer.Metric.unit(),
          outbound_demand_unit: Buffer.Metric.unit(),
          demand_counter: DemandCounter.t(),
          demand_pad: Pad.ref(),
          log_tag: String.t(),
          target_size: pos_integer() | nil,
          min_demand_factor: pos_integer() | nil
        }) :: t()
  def init(config) do
    %{
      inbound_demand_unit: inbound_demand_unit,
      outbound_demand_unit: outbound_demand_unit,
      demand_counter: demand_counter,
      demand_pad: demand_pad,
      log_tag: log_tag,
      target_size: target_size,
      min_demand_factor: min_demand_factor
    } = config

    inbound_metric = Buffer.Metric.from_unit(inbound_demand_unit)
    outbound_metric = Buffer.Metric.from_unit(outbound_demand_unit)

    default_target_size = inbound_metric.buffer_size_approximation() * @default_target_size_factor

    target_size = target_size || default_target_size

    min_demand =
      (target_size * (min_demand_factor || default_min_demand_factor())) |> ceil() |> max(1)

    %__MODULE__{
      q: @qe.new(),
      log_tag: log_tag,
      target_size: target_size,
      size: 0,
      demand: target_size,
      min_demand: min_demand,
      inbound_metric: inbound_metric,
      outbound_metric: outbound_metric,
      demand_counter: demand_counter
    }
    |> send_demands(demand_pad)
  end

  @spec store(t(), atom(), any()) :: t()
  def store(input_queue, type \\ :buffers, v)

  def store(input_queue, :buffers, v) when is_list(v) do
    %__MODULE__{size: size, target_size: target_size} = input_queue

    if size >= target_size do
      """
      Received buffers despite not requesting them.
      It is probably caused by overestimating demand by previous element.
      """
      |> mk_log(input_queue)
      |> Membrane.Logger.debug_verbose()
    end

    %__MODULE__{size: size} = input_queue = do_store_buffers(input_queue, v)

    Telemetry.report_metric(:store, size, input_queue.log_tag)

    input_queue
  end

  def store(input_queue, :buffer, v), do: store(input_queue, :buffers, [v])

  def store(%__MODULE__{q: q, size: size} = input_queue, type, v)
      when type in @non_buf_types do
    "Storing #{type}" |> mk_log(input_queue) |> Membrane.Logger.debug_verbose()

    Telemetry.report_metric(:store, size, input_queue.log_tag)

    %__MODULE__{input_queue | q: q |> @qe.push({:non_buffer, type, v})}
  end

  defp do_store_buffers(
         %__MODULE__{
           q: q,
           size: size,
           inbound_metric: inbound_metric,
           outbound_metric: outbound_metric
         } = input_queue,
         v
       ) do
    inbound_metric_buffer_size = inbound_metric.buffers_size(v)
    outbound_metric_buffer_size = outbound_metric.buffers_size(v)

    "Storing #{inspect(inbound_metric_buffer_size)} buffers"
    |> mk_log(input_queue)
    |> Membrane.Logger.debug_verbose()

    %__MODULE__{
      input_queue
      | q: q |> @qe.push({:buffers, v, inbound_metric_buffer_size, outbound_metric_buffer_size}),
        size: size + inbound_metric_buffer_size
    }
  end

  @spec take_and_demand(t(), non_neg_integer(), Pad.ref()) :: {output(), t()}
  def take_and_demand(
        %__MODULE__{} = input_queue,
        count,
        demand_pad
      )
      when count >= 0 do
    "Taking #{inspect(count)} #{inspect(input_queue.outbound_metric)}"
    |> mk_log(input_queue)
    |> Membrane.Logger.debug_verbose()

    {out, %__MODULE__{size: new_size} = input_queue} = do_take(input_queue, count)
    input_queue = send_demands(input_queue, demand_pad)
    Telemetry.report_metric(:take_and_demand, new_size, input_queue.log_tag)
    {out, input_queue}
  end

  defp do_take(
         %__MODULE__{
           q: q,
           size: size,
           inbound_metric: inbound_metric,
           outbound_metric: outbound_metric,
           demand: demand
         } = input_queue,
         count
       ) do
    {out, nq, new_queue_size} = q |> q_pop(count, inbound_metric, outbound_metric, size)
    new_demand_size = demand + (size - new_queue_size)

    {out,
     %__MODULE__{
       input_queue
       | q: nq,
         size: new_queue_size,
         demand: new_demand_size
     }}
  end

  defp q_pop(
         q,
         size_to_take_in_outbound_metric,
         inbound_metric,
         outbound_metric,
         queue_size,
         acc \\ []
       )

  defp q_pop(
         q,
         size_to_take_in_outbound_metric,
         inbound_metric,
         outbound_metric,
         queue_size,
         acc
       )
       when size_to_take_in_outbound_metric > 0 do
    q
    |> @qe.pop
    |> case do
      {{:value, {:buffers, buffers, inbound_metric_buf_size, _outbound_metric_buf_size}}, nq} ->
        {buffers, excess_buffers} =
          outbound_metric.split_buffers(buffers, size_to_take_in_outbound_metric)

        buffers_size_inbound_metric = inbound_metric.buffers_size(buffers)
        buffers_size_outbound_metric = outbound_metric.buffers_size(buffers)

        case excess_buffers do
          [] ->
            q_pop(
              nq,
              size_to_take_in_outbound_metric - buffers_size_outbound_metric,
              inbound_metric,
              outbound_metric,
              queue_size - inbound_metric_buf_size,
              [
                {:buffers, buffers, buffers_size_inbound_metric, buffers_size_outbound_metric}
                | acc
              ]
            )

          non_empty_excess_buffers ->
            excess_buffers_inbound_metric_size =
              inbound_metric.buffers_size(non_empty_excess_buffers)

            excess_buffers_outbound_metric_size =
              outbound_metric.buffers_size(non_empty_excess_buffers)

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
          [
            {type, e} | acc
          ]
        )
    end
  end

  defp q_pop(q, 0, inbound_metric, outbound_metric, queue_size, acc) do
    q
    |> @qe.pop
    |> case do
      {{:value, {:non_buffer, type, e}}, nq} ->
        q_pop(nq, 0, inbound_metric, outbound_metric, queue_size, [{type, e} | acc])

      _empty_or_buffer ->
        {{:value, acc |> Enum.reverse()}, q, queue_size}
    end
  end

  @spec send_demands(t(),  Pad.ref()) :: t()
  defp send_demands(
         %__MODULE__{
           size: size,
           target_size: target_size,
           demand: demand,
           demand_counter: demand_counter,
           min_demand: min_demand
         } = input_queue,
                  linked_output_ref
       )
       when size < target_size and demand > 0 do
    to_demand = max(demand, min_demand)

    """
    Sending demand of size #{inspect(to_demand)} to output #{inspect(linked_output_ref)}
    """
    |> mk_log(input_queue)
    |> Membrane.Logger.debug_verbose()

    :ok = DemandCounter.increase(demand_counter, to_demand)
    %__MODULE__{input_queue | demand: demand - to_demand}
  end

  defp send_demands(input_queue, _linked_output_ref) do
    input_queue
  end

  # This function may be unused if particular logs are pruned
  @dialyzer {:no_unused, mk_log: 2}
  defp mk_log(message, input_queue) do
    %__MODULE__{
      log_tag: log_tag,
      size: size,
      target_size: target_size,
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
end
