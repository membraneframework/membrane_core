defmodule Membrane.Core.Element.Toilet do
  @moduledoc false

  # Toilet is an entity that can be urinated to and rinsed. If it's not rinsed on
  # time and exceeds its capacity, it overflows by logging an error and killing
  # the responsible process (passed on the toilet creation).

  require Membrane.Logger

  @opaque t :: {__MODULE__, :atomics.atomics_ref(), pos_integer, Process.dest()}

  @spec default_capacity_factor() :: number
  def default_capacity_factor, do: 200

  @spec new(pos_integer() | nil, Membrane.Buffer.Metric.unit_t(), Process.dest()) :: t
  def new(capacity_factor, demand_unit, responsible_process) do
    capacity =
      Membrane.Buffer.Metric.from_unit(demand_unit).buffer_size_approximation() *
        (capacity_factor || default_capacity_factor())

    capacity = ceil(capacity)
    {__MODULE__, :atomics.new(1, []), capacity, responsible_process}
  end

  @spec urinate(t, non_neg_integer) :: :ok
  def urinate({__MODULE__, atomic, capacity, responsible_process}, amount) do
    size = :atomics.add_get(atomic, 1, amount)
    if size > capacity, do: overflow(size, capacity, responsible_process)
    :ok
  end

  @spec rinse(t, non_neg_integer) :: :ok
  def rinse({__MODULE__, atomic, _capacity, _responsible_process}, amount) do
    :atomics.sub(atomic, 1, amount)
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
    You can also try changing the `toilet_capacity_factor` in `Membrane.ParentSpec.via_in/3`.
    """)

    Process.exit(responsible_process, :kill)
  end
end
