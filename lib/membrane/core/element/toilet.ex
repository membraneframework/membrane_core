defmodule Membrane.Core.Element.Toilet do
  @moduledoc false

  # Toilet is an entity that can be filled and drained. If it's not drained on
  # time and exceeds its capacity, it overflows by logging an error and killing
  # the responsible process (passed on the toilet creation).

  require Membrane.Logger

  defmodule DistributedCounter do
    @moduledoc false

    # A module providing a common interface to access and modify a counter used in the toilet implementation.
    # The counter uses :atomics module under the hood.
    # The module allows to create and modify the value of a counter in the same manner both when the counter is about to be accessed
    # from the same node, and from different nodes.

    defmodule Worker do
      @moduledoc false

      # This is a GenServer created when the counter is about to be accessed from different nodes - it's running on the same node,
      # where the :atomics variable is put, and processes from different nodes can ask it to modify the counter on their behalf.

      use GenServer

      @impl true
      def init(parent_pid) do
        Process.monitor(parent_pid)
        {:ok, nil, :hibernate}
      end

      @impl true
      def handle_call({:add_get, atomic_ref, value}, _from, _state) do
        result = :atomics.add_get(atomic_ref, 1, value)
        {:reply, result, nil}
      end

      @impl true
      def handle_cast({:sub, atomic_ref, value}, _state) do
        :atomics.sub(atomic_ref, 1, value)
        {:noreply, nil}
      end

      @impl true
      def handle_info({:DOWN, _ref, :process, _object, _reason}, state) do
        {:stop, :normal, state}
      end
    end

    @type t :: {pid(), :atomics.atomics_ref()}

    @spec new() :: t
    def new() do
      atomic_ref = :atomics.new(1, [])
      {:ok, pid} = GenServer.start(Worker, self())
      {pid, atomic_ref}
    end

    @spec add_get(t, integer()) :: integer()
    def add_get({pid, atomic_ref}, value) when node(pid) == node(self()) do
      :atomics.add_get(atomic_ref, 1, value)
    end

    def add_get({pid, atomic_ref}, value) do
      GenServer.call(pid, {:add_get, atomic_ref, value})
    end

    @spec sub(t, integer()) :: :ok
    def sub({pid, atomic_ref}, value) when node(pid) == node(self()) do
      :atomics.sub(atomic_ref, 1, value)
    end

    def sub({pid, atomic_ref}, value) do
      GenServer.cast(pid, {:sub, atomic_ref, value})
    end
  end

  @opaque t ::
            {__MODULE__, DistributedCounter.t(), pos_integer, Process.dest(), pos_integer(),
             non_neg_integer()}

  @default_capacity_factor 200

  @spec new(
          pos_integer() | nil,
          Membrane.Buffer.Metric.unit_t(),
          Process.dest(),
          pos_integer()
        ) :: t
  def new(capacity, demand_unit, responsible_process, throttling_factor) do
    default_capacity =
      Membrane.Buffer.Metric.from_unit(demand_unit).buffer_size_approximation() *
        @default_capacity_factor

    toilet_ref = DistributedCounter.new()
    capacity = capacity || default_capacity
    {__MODULE__, toilet_ref, capacity, responsible_process, throttling_factor, 0}
  end

  @spec fill(t, non_neg_integer) :: {:ok | :overflow, t}
  def fill(
        {__MODULE__, counter, capacity, responsible_process, throttling_factor,
         unrinsed_buffers_size},
        amount
      ) do
    if unrinsed_buffers_size + amount < throttling_factor do
      {:ok,
       {__MODULE__, counter, capacity, responsible_process, throttling_factor,
        amount + unrinsed_buffers_size}}
    else
      size = DistributedCounter.add_get(counter, amount + unrinsed_buffers_size)

      if size > capacity do
        overflow(size, capacity, responsible_process)
        {:overflow, {__MODULE__, counter, capacity, responsible_process, throttling_factor, 0}}
      else
        {:ok, {__MODULE__, counter, capacity, responsible_process, throttling_factor, 0}}
      end
    end
  end

  @spec drain(t, non_neg_integer) :: :ok
  def drain(
        {__MODULE__, counter, _capacity, _responsible_process, _throttling_factor,
         _unrinsed_buff_size},
        amount
      ) do
    DistributedCounter.sub(counter, amount)
  end

  defp overflow(size, capacity, responsible_process) do
    Membrane.Logger.debug_verbose(~S"""
    Toilet overflow

                 ` ' `
             .'''. ' .'''.
               .. ' ' ..
              '  '.'.'  '
              .'''.'.'''.
             ' .''.'.''. '
           ;------ ' ------;
           | ~~ .--'--//   |
           |   /   '   \   |
           |  /    '    \  |
           |  |    '    |  |  ,----.
           |   \ , ' , /   | =|____|=
           '---,###'###,---'  (---(
              /##  '  ##\      )---)
              |##, ' ,##|     (---(
               \'#####'/       `---`
                \`"#"`/
                 |`"`|
               .-|   |-.
          jgs /  '   '  \
              '---------'
    """)

    Membrane.Logger.error("""
    Toilet overflow.

    Reached the size of #{inspect(size)}, which is above toilet capacity (#{inspect(capacity)})
    when storing data from output working in push mode. It means that some element in the pipeline
    processes the stream too slow or doesn't process it at all.
    To have control over amount of buffers being produced, consider using output in pull mode
    (see `Membrane.Pad.mode_t`).
    You can also try changing the `toilet_capacity` in `Membrane.ChildrenSpec.via_in/3`.
    """)

    Process.exit(responsible_process, :kill)
  end
end
