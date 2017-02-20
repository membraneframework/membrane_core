defmodule Membrane.Time do
  @moduledoc """
  Module containing functions needed to perform handling of time.

  Membrane always internally uses nanosecond as a time unit. This is how all time
  units should represented in the code unless there's a good reason to act
  differently.

  Please note that Erlang VM may internally use different units and that may
  differ from platform to platform. Still, unless you need to perform calculations
  that do not touch hardware clock, you should use Membrane units for consistency.
  """

  @compile {:inline, [
    nanosecond: 1,
    nanoseconds: 1,
    microsecond: 1,
    microseconds: 1,
    millisecond: 1,
    milliseconds: 1,
    second: 1,
    seconds: 1,
    minute: 1,
    minutes: 1,
    hour: 1,
    hours: 1,
    day: 1,
    days: 1,
  ]}

  @type t :: pos_integer
  @type native_t :: integer


  @doc """
  Returns internal Erlang VM clock resolution.

  It will return integer that tells how many "ticks" the VM is handling
  within a second.
  """
  @spec native_resolution() :: pos_integer
  def native_resolution do
    System.convert_time_unit(1, :seconds, :native)
  end


  @doc """
  Returns current monotonic time.

  It is a wrapper around `System.monotonic_time/0` made mostly for purpose
  of mocking such calls in specs.
  """
  @spec native_monotonic_time() :: native_t
  def native_monotonic_time do
    System.monotonic_time()
  end


  @doc """
  Returns given nanoseconds in internal Membrane time units.

  Inlined by the compiler.
  """
  @spec nanosecond(pos_integer) :: t
  def nanosecond(value) when is_integer(value) and value >= 0 do
    value
  end


  @doc """
  The same as `nanosecond/1`.

  Inlined by the compiler.
  """
  @spec nanoseconds(pos_integer) :: t
  def nanoseconds(value) when is_integer(value) and value >= 0 do
    nanosecond(value)
  end


  @doc """
  Returns given microseconds in internal Membrane time units.

  Inlined by the compiler.
  """
  @spec microsecond(pos_integer) :: t
  def microsecond(value) when is_integer(value) and value >= 0 do
    value * 1_000
  end


  @doc """
  The same as `microsecond/1`.

  Inlined by the compiler.
  """
  @spec microseconds(pos_integer) :: t
  def microseconds(value) when is_integer(value) and value >= 0 do
    microsecond(value)
  end


  @doc """
  Returns given milliseconds in internal Membrane time units.

  Inlined by the compiler.
  """
  @spec millisecond(pos_integer) :: t
  def millisecond(value) when is_integer(value) and value >= 0 do
    value * 1_000_000
  end


  @doc """
  The same as `millisecond/1`.

  Inlined by the compiler.
  """
  @spec milliseconds(pos_integer) :: t
  def milliseconds(value) when is_integer(value) and value >= 0 do
    millisecond(value)
  end


  @doc """
  Returns given seconds in internal Membrane time units.

  Inlined by the compiler.
  """
  @spec second(pos_integer) :: t
  def second(value) when is_integer(value) and value >= 0 do
    value * 1_000_000_000
  end


  @doc """
  The same as `second/1`.

  Inlined by the compiler.
  """
  @spec seconds(pos_integer) :: t
  def seconds(value) when is_integer(value) and value >= 0 do
    second(value)
  end


  @doc """
  Returns given minutes in internal Membrane time units.

  Inlined by the compiler.
  """
  @spec minute(pos_integer) :: t
  def minute(value) when is_integer(value) and value >= 0 do
    value * 60_000_000_000
  end


  @doc """
  The same as `minute/1`.

  Inlined by the compiler.
  """
  @spec minutes(pos_integer) :: t
  def minutes(value) when is_integer(value) and value >= 0 do
    minute(value)
  end


  @doc """
  Returns given hours in internal Membrane time units.

  Inlined by the compiler.
  """
  @spec hour(pos_integer) :: t
  def hour(value) when is_integer(value) and value >= 0 do
    value * 3_600_000_000_000
  end


  @doc """
  The same as `hour/1`.

  Inlined by the compiler.
  """
  @spec hours(pos_integer) :: t
  def hours(value) when is_integer(value) and value >= 0 do
    hour(value)
  end


  @doc """
  Returns given days in internal Membrane time units.

  Inlined by the compiler.
  """
  @spec day(pos_integer) :: t
  def day(value) when is_integer(value) and value >= 0 do
    value * 86_400_000_000_000
  end


  @doc """
  The same as `day/1`.

  Inlined by the compiler.
  """
  @spec days(pos_integer) :: t
  def days(value) when is_integer(value) and value >= 0 do
    day(value)
  end
end
