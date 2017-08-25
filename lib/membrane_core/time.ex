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
    monotonic_time: 0,
    system_time: 0,
    from_datetime: 1,
    from_iso8601!: 1,
    native_unit: 1,
    native_units: 1,
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
    to_datetime: 1,
    to_iso8601: 1,
    to_native_units: 1,
    to_nanoseconds: 1,
    to_microseconds: 1,
    to_milliseconds: 1,
    to_seconds: 1,
    to_minutes: 1,
    to_hours: 1,
    to_days: 1,
  ]}

  @type t :: integer
  @type native_t :: integer


  @doc """
  Checks whether value is Membrane.Time.t
  """
  @spec is_t(any) :: boolean
  defmacro is_t(value) do
    quote do is_integer(unquote value) end
  end


  @doc """
  Checks whether value is Membrane.Time.native_t
  """
  @spec is_native_t(any) :: boolean
  defmacro is_native_t(value) do
    quote do is_integer(unquote value) end
  end


  @doc """
  Returns current monotonic time based on System.monotonic_time/0
  in internal Membrane time units.

  Inlined by the compiler.
  """
  @spec monotonic_time() :: t
  def monotonic_time do
    System.monotonic_time |> native_units
  end


  @doc """
  Returns current POSIX time based on System.system_time/0
  in internal Membrane time units.

  Inlined by the compiler.
  """
  @spec system_time() :: t
  def system_time do
    System.system_time |> native_units
  end


  @doc """
  Converts `DateTime` to internal Membrane time units.

  Inlined by the compiler.
  """
  @spec from_datetime(DateTime.t) :: t
  def from_datetime(value = %DateTime{}) do
    value |> DateTime.to_unix(:nanosecond) |> nanoseconds
  end


  @doc """
  Converts iso8601 string to internal Membrane time units.
  If input is invalid, throws match error.

  Inlined by the compiler.
  """
  @spec from_iso8601!(String.t) :: t
  def from_iso8601!(value) when is_binary(value) do
    {:ok, datetime, shift} = value |> DateTime.from_iso8601
    (datetime |> from_datetime) + (shift |> seconds)
  end


  @doc """
  Returns given native units in internal Membrane time units.

  Inlined by the compiler.
  """
  @spec native_unit(native_t) :: t
  def native_unit(value) when is_integer(value) do
    value |> System.convert_time_unit(:native, :nanosecond) |> nanoseconds
  end


  @doc """
  The same as `native_unit/1`.

  Inlined by the compiler.
  """
  @spec native_units(native_t) :: t
  def native_units(value) when is_integer(value) do
    native_unit(value)
  end


  @doc """
  Returns given nanoseconds in internal Membrane time units.

  Inlined by the compiler.
  """
  @spec nanosecond(integer) :: t
  def nanosecond(value) when is_integer(value) do
    value
  end


  @doc """
  The same as `nanosecond/1`.

  Inlined by the compiler.
  """
  @spec nanoseconds(integer) :: t
  def nanoseconds(value) when is_integer(value) do
    nanosecond(value)
  end


  @doc """
  Returns given microseconds in internal Membrane time units.

  Inlined by the compiler.
  """
  @spec microsecond(integer) :: t
  def microsecond(value) when is_integer(value) do
    value * 1_000
  end


  @doc """
  The same as `microsecond/1`.

  Inlined by the compiler.
  """
  @spec microseconds(integer) :: t
  def microseconds(value) when is_integer(value) do
    microsecond(value)
  end


  @doc """
  Returns given milliseconds in internal Membrane time units.

  Inlined by the compiler.
  """
  @spec millisecond(integer) :: t
  def millisecond(value) when is_integer(value) do
    value * 1_000_000
  end


  @doc """
  The same as `millisecond/1`.

  Inlined by the compiler.
  """
  @spec milliseconds(integer) :: t
  def milliseconds(value) when is_integer(value) do
    millisecond(value)
  end


  @doc """
  Returns given seconds in internal Membrane time units.

  Inlined by the compiler.
  """
  @spec second(integer) :: t
  def second(value) when is_integer(value) do
    value * 1_000_000_000
  end


  @doc """
  The same as `second/1`.

  Inlined by the compiler.
  """
  @spec seconds(integer) :: t
  def seconds(value) when is_integer(value) do
    second(value)
  end


  @doc """
  Returns given minutes in internal Membrane time units.

  Inlined by the compiler.
  """
  @spec minute(integer) :: t
  def minute(value) when is_integer(value) do
    value * 60_000_000_000
  end


  @doc """
  The same as `minute/1`.

  Inlined by the compiler.
  """
  @spec minutes(integer) :: t
  def minutes(value) when is_integer(value) do
    minute(value)
  end


  @doc """
  Returns given hours in internal Membrane time units.

  Inlined by the compiler.
  """
  @spec hour(integer) :: t
  def hour(value) when is_integer(value) do
    value * 3_600_000_000_000
  end


  @doc """
  The same as `hour/1`.

  Inlined by the compiler.
  """
  @spec hours(integer) :: t
  def hours(value) when is_integer(value) do
    hour(value)
  end


  @doc """
  Returns given days in internal Membrane time units.

  Inlined by the compiler.
  """
  @spec day(integer) :: t
  def day(value) when is_integer(value) do
    value * 86_400_000_000_000
  end


  @doc """
  The same as `day/1`.

  Inlined by the compiler.
  """
  @spec days(integer) :: t
  def days(value) when is_integer(value) do
    day(value)
  end

  @doc """
  Returns time as a `DateTime` struct. TimeZone is set to UTC.

  Inlined by the compiler.
  """
  @spec to_datetime(t) :: DateTime.t
  def to_datetime(value) when is_t(value) do
     DateTime.from_unix!(value |> nanoseconds, :nanosecond)
  end

  @doc """
  Returns time as a iso8601 string.

  Inlined by the compiler.
  """
  @spec to_iso8601(t) :: String.t
  def to_iso8601(value) when is_t(value) do
    value |> to_datetime |> DateTime.to_iso8601
  end


  @doc """
  Returns time in system native units. Rounded using Kernel.round/1

  Inlined by the compiler.
  """
  @spec to_native_units(t) :: native_t
  def to_native_units(value) when is_t(value) do
    value / (1 |> native_unit) |> round
  end


  @doc """
  Returns time in nanoseconds. Rounded using Kernel.round/1

  Inlined by the compiler.
  """
  @spec to_nanoseconds(t) :: integer
  def to_nanoseconds(value) when is_t(value) do
    value / (1 |> nanosecond) |> round
  end


  @doc """
  Returns time in microseconds. Rounded using Kernel.round/1

  Inlined by the compiler.
  """
  @spec to_microseconds(t) :: integer
  def to_microseconds(value) when is_t(value) do
    value / (1 |> microsecond) |> round
  end


  @doc """
  Returns time in milliseconds. Rounded using Kernel.round/1

  Inlined by the compiler.
  """
  @spec to_milliseconds(t) :: integer
  def to_milliseconds(value) when is_t(value) do
    value / (1 |> millisecond) |> round
  end


  @doc """
  Returns time in seconds. Rounded using Kernel.round/1

  Inlined by the compiler.
  """
  @spec to_seconds(t) :: integer
  def to_seconds(value) when is_t(value) do
    value / (1 |> second) |> round
  end


  @doc """
  Returns time in minutes. Rounded using Kernel.round/1

  Inlined by the compiler.
  """
  @spec to_minutes(t) :: integer
  def to_minutes(value) when is_t(value) do
    value / (1 |> minute) |> round
  end


  @doc """
  Returns time in hours. Rounded using Kernel.round/1

  Inlined by the compiler.
  """
  @spec to_hours(t) :: integer
  def to_hours(value) when is_t(value) do
    value / (1 |> hour) |> round
  end


  @doc """
  Returns time in days. Rounded using Kernel.round/1

  Inlined by the compiler.
  """
  @spec to_days(t) :: integer
  def to_days(value) when is_t(value) do
    value / (1 |> day) |> round
  end

end
