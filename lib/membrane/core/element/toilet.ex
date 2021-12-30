defmodule Membrane.Core.Element.Toilet do
  @moduledoc false

  # Toilet is an entity that can be urinated to and rinsed. If it's not rinsed on
  # time and exceeds its capacity, it overflows by logging an error and killing
  # the responsible process (passed on the toilet creation).

  require Membrane.Logger

  @opaque t :: {__MODULE__, :atomics.atomics_ref(), pos_integer, Process.dest()}

  @spec new(pos_integer(), Process.dest()) :: t
  def new(capacity, responsible_process) do
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

    Reached the size of #{inspect(size)},
    which is above fail level (#{inspect(capacity)}) when storing data from output working in push mode.
    To have control over amount of buffers being produced, consider using pull mode.
    """)

    Process.exit(responsible_process, :kill)
  end
end
