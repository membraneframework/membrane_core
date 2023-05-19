defmodule Membrane.Core.Element.InputQueue do
  @moduledoc false
  # Queue that is attached to the `:input` pad when working in a `:manual` flow control mode.

  # It stores `Membrane.Buffer`, `Membrane.Event` and `Membrane.StreamFormat` structs and
  # prevents the situation where the data in a stream contains the discontinuities.
  # It also guarantees that element won't be flooded with the incoming data.

  use Bunch

  alias Membrane.Buffer
  alias Membrane.Core.Element.AtomicDemand
  alias Membrane.Event
  alias Membrane.Pad
  alias Membrane.StreamFormat

  require Membrane.Core.Telemetry, as: Telemetry
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
          linked_output_ref: Pad.ref(),
          atomic_demand: AtomicDemand.t()
        }

  @enforce_keys [
    :q,
    :log_tag,
    :target_size,
    :atomic_demand,
    :inbound_metric,
    :outbound_metric,
    :linked_output_ref
  ]

  defstruct @enforce_keys ++ [size: 0, demand: 0]

  @default_target_size_factor 40

  @spec default_min_demand_factor() :: number()
  def default_min_demand_factor, do: 0.25

  @spec init(%{
          inbound_demand_unit: Buffer.Metric.unit(),
          outbound_demand_unit: Buffer.Metric.unit(),
          atomic_demand: AtomicDemand.t(),
          linked_output_ref: Pad.ref(),
          log_tag: String.t(),
          target_size: pos_integer() | nil
        }) :: t()
  def init(config) do
    %{
      inbound_demand_unit: inbound_demand_unit,
      outbound_demand_unit: outbound_demand_unit,
      atomic_demand: atomic_demand,
      linked_output_ref: linked_output_ref,
      log_tag: log_tag,
      target_size: target_size
    } = config

    inbound_metric = Buffer.Metric.from_unit(inbound_demand_unit)
    outbound_metric = Buffer.Metric.from_unit(outbound_demand_unit)

    default_target_size = inbound_metric.buffer_size_approximation() * @default_target_size_factor

    target_size = target_size || default_target_size

    %__MODULE__{
      q: @qe.new(),
      log_tag: log_tag,
      target_size: target_size,
      inbound_metric: inbound_metric,
      outbound_metric: outbound_metric,
      atomic_demand: atomic_demand,
      linked_output_ref: linked_output_ref
    }
    |> maybe_increase_atomic_demand()
  end

  @spec store(t(), atom(), queue_item() | [queue_item()]) :: t()
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
           demand: demand,
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
        size: size + inbound_metric_buffer_size,
        demand: demand - inbound_metric_buffer_size
    }
  end

  @spec take(t, non_neg_integer()) :: {output(), t}
  def take(%__MODULE__{} = input_queue, count) when count >= 0 do
    "Taking #{inspect(count)} #{inspect(input_queue.outbound_metric)}"
    |> mk_log(input_queue)
    |> Membrane.Logger.debug_verbose()

    {out, input_queue} = do_take(input_queue, count)
    input_queue = maybe_increase_atomic_demand(input_queue)

    Telemetry.report_metric(:take, input_queue.size, input_queue.log_tag)

    {out, input_queue}
  end

  defp do_take(
         %__MODULE__{
           q: q,
           size: size,
           inbound_metric: inbound_metric,
           outbound_metric: outbound_metric
         } = input_queue,
         count
       ) do
    {out, nq, new_size} = q |> q_pop(count, inbound_metric, outbound_metric, size)
    input_queue = %{input_queue | q: nq, size: new_size}
    {out, input_queue}
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
    Increasing AtomicDemand linked to  #{inspect(input_queue.linked_output_ref)} by #{inspect(diff)}
    """
    |> mk_log(input_queue)
    |> Membrane.Logger.debug_verbose()

    :ok = AtomicDemand.increase(atomic_demand, diff)
    %{input_queue | demand: demand + diff}
  end

  defp maybe_increase_atomic_demand(%__MODULE__{} = input_queue), do: input_queue

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
end
