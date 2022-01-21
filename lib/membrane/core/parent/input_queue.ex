defmodule Membrane.Core.Element.InputQueue do
  @moduledoc false
  # Queue that is attached to the `:input` pad when working in a `:pull` mode.

  # It stores `Membrane.Buffer`, `Membrane.Event` and `Membrane.Caps` structs and
  # prevents the situation where the data in a stream contains the discontinuities.
  # It also guarantees that element won't be flooded with the incoming data.

  use Bunch

  alias Membrane.Buffer
  alias Membrane.Core.{Message, Telemetry}
  alias Membrane.Pad

  require Membrane.Core.Message
  require Membrane.Core.Telemetry
  require Membrane.Logger

  @qe Qex

  @non_buf_types [:event, :caps]

  @type output_value_t :: {:event | :caps, any} | {:buffers, list, pos_integer}
  @type output_t :: {:empty | :value, [output_value_t]}

  @type t :: %__MODULE__{
          q: @qe.t(),
          log_tag: String.t(),
          demand_excess: pos_integer(),
          size: non_neg_integer(),
          demand: non_neg_integer(),
          min_demand: pos_integer(),
          metric: module(),
          toilet?: boolean()
        }

  @enforce_keys [
    :q,
    :log_tag,
    :demand_excess,
    :size,
    :demand,
    :min_demand,
    :metric,
    :toilet?
  ]

  defstruct @enforce_keys

  @default_demand_excess_factor 40

  @spec default_min_demand_factor() :: number()
  def default_min_demand_factor, do: 0.25

  @spec init(%{
          demand_unit: Buffer.Metric.unit_t(),
          demand_pid: pid(),
          demand_pad: Pad.ref_t(),
          log_tag: String.t(),
          toilet?: boolean(),
          demand_excess: pos_integer() | nil,
          min_demand_factor: pos_integer() | nil
        }) :: t()
  def init(config) do
    %{
      demand_unit: demand_unit,
      demand_pid: demand_pid,
      demand_pad: demand_pad,
      log_tag: log_tag,
      toilet?: toilet?,
      demand_excess: demand_excess,
      min_demand_factor: min_demand_factor
    } = config

    metric = Buffer.Metric.from_unit(demand_unit)

    default_demand_excess = metric.buffer_size_approximation() * @default_demand_excess_factor
    demand_excess = demand_excess || default_demand_excess

    min_demand =
      (demand_excess * (min_demand_factor || default_min_demand_factor())) |> ceil() |> max(1)

    %__MODULE__{
      q: @qe.new(),
      log_tag: log_tag,
      demand_excess: demand_excess,
      size: 0,
      demand: demand_excess,
      min_demand: min_demand,
      metric: metric,
      toilet?: toilet?
    }
    |> send_demands(demand_pid, demand_pad)
  end

  @spec store(t(), atom(), any()) :: t()
  def store(input_queue, type \\ :buffers, v)

  def store(input_queue, :buffers, v) when is_list(v) do
    %__MODULE__{size: size, demand_excess: demand_excess} = input_queue

    if size >= demand_excess do
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

  defp do_store_buffers(%__MODULE__{q: q, size: size, metric: metric} = input_queue, v) do
    buf_cnt = v |> metric.buffers_size

    "Storing #{inspect(buf_cnt)} buffers"
    |> mk_log(input_queue)
    |> Membrane.Logger.debug_verbose()

    %__MODULE__{
      input_queue
      | q: q |> @qe.push({:buffers, v, buf_cnt}),
        size: size + buf_cnt
    }
  end

  @spec take_and_demand(t(), non_neg_integer(), pid(), Pad.ref_t()) :: {output_t(), t()}
  def take_and_demand(
        %__MODULE__{size: size} = input_queue,
        count,
        demand_pid,
        demand_pad
      )
      when count >= 0 do
    "Taking #{inspect(count)} buffers" |> mk_log(input_queue) |> Membrane.Logger.debug_verbose()
    {out, %__MODULE__{size: new_size} = input_queue} = do_take(input_queue, count)

    input_queue =
      input_queue
      |> Bunch.Struct.update_in(:demand, &(&1 + size - new_size))
      |> send_demands(demand_pid, demand_pad)

    Telemetry.report_metric(:take_and_demand, new_size, input_queue.log_tag)

    {out, input_queue}
  end

  defp do_take(%__MODULE__{q: q, size: size, metric: metric} = input_queue, count) do
    {out, nq} = q |> q_pop(count, metric)
    {out, %__MODULE__{input_queue | q: nq, size: max(0, size - count)}}
  end

  defp q_pop(q, count, metric, acc \\ [])

  defp q_pop(q, count, metric, acc) when count > 0 do
    q
    |> @qe.pop
    |> case do
      {{:value, {:buffers, b, buf_cnt}}, nq} when count >= buf_cnt ->
        q_pop(nq, count - buf_cnt, metric, [{:buffers, b, buf_cnt} | acc])

      {{:value, {:buffers, b, buf_cnt}}, nq} when count < buf_cnt ->
        {b, back} = b |> metric.split_buffers(count)
        nq = nq |> @qe.push_front({:buffers, back, buf_cnt - count})
        {{:value, [{:buffers, b, count} | acc] |> Enum.reverse()}, nq}

      {:empty, nq} ->
        {{:empty, acc |> Enum.reverse()}, nq}

      {{:value, {:non_buffer, type, e}}, nq} ->
        q_pop(nq, count, metric, [{type, e} | acc])
    end
  end

  defp q_pop(q, 0, metric, acc) do
    q
    |> @qe.pop
    |> case do
      {{:value, {:non_buffer, type, e}}, nq} -> q_pop(nq, 0, metric, [{type, e} | acc])
      _empty_or_buffer -> {{:value, acc |> Enum.reverse()}, q}
    end
  end

  @spec send_demands(t(), pid(), Pad.ref_t()) :: t()
  defp send_demands(
         %__MODULE__{
           toilet?: false,
           size: size,
           demand_excess: demand_excess,
           demand: demand,
           min_demand: min_demand
         } = input_queue,
         demand_pid,
         linked_output_ref
       )
       when size < demand_excess and demand > 0 do
    to_demand = max(demand, min_demand)

    """
    Sending demand of size #{inspect(to_demand)} to input #{inspect(linked_output_ref)}
    """
    |> mk_log(input_queue)
    |> Membrane.Logger.debug_verbose()

    Message.send(demand_pid, :demand, to_demand, for_pad: linked_output_ref)
    %__MODULE__{input_queue | demand: demand - to_demand}
  end

  defp send_demands(input_queue, _demand_pid, _linked_output_ref) do
    input_queue
  end

  # This function may be unused if particular logs are pruned
  @dialyzer {:no_unused, mk_log: 2}
  defp mk_log(message, input_queue) do
    %__MODULE__{
      log_tag: log_tag,
      size: size,
      demand_excess: demand_excess,
      toilet?: toilet
    } = input_queue

    [
      "InputQueue #{log_tag}#{if toilet, do: " (toilet)", else: ""}: ",
      message,
      "\n",
      "InputQueue size: #{inspect(size)}, demand excess: #{inspect(demand_excess)}"
    ]
  end

  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{size: size}), do: size == 0
end
