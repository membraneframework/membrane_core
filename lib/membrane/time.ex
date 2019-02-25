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

  @compile {:inline,
            [
              pretty_now: 0,
              monotonic_time: 0,
              system_time: 0,
              os_time: 0,
              vm_time: 0,
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
              to_days: 1
            ]}

  @type t :: integer
  @type non_neg_t :: non_neg_integer
  @type native_t :: integer

  @units_abbreviations %{
    days: "d",
    hours: "h",
    minutes: "min",
    seconds: "s",
    milliseconds: "ms",
    microseconds: "us",
    nanoseconds: "ns"
  }

  @doc """
  Checks whether value is Membrane.Time.t
  """
  defguard is_t(value) when is_integer(value)

  @doc """
  Checks whether value is Membrane.Time.native_t
  """
  defguard is_native_t(value) when is_integer(value)

  @doc """
  Returns duration as a string with unit. Chosen unit is the biggest possible
  that doesn't involve precission loss.

  ## Examples

      iex> import #{inspect(__MODULE__)}
      iex> 10 |> milliseconds() |> pretty_duration()
      "10 ms"
      iex> 60_000_000 |> microseconds() |> pretty_duration()
      "1 min"
      iex> 2 |> nanoseconds() |> pretty_duration()
      "2 ns"

  """
  @spec pretty_duration(t) :: String.t()
  def pretty_duration(time) when is_t(time) do
    {time, unit} = time |> best_unit()

    "#{time} #{@units_abbreviations[unit]}"
  end

  @doc """
  Returns quoted code producing given amount time. Chosen unit is the biggest possible
  that doesn't involve precission loss.

  ## Examples

      iex> import #{inspect(__MODULE__)}
      iex> 10 |> milliseconds() |> to_code() |> Macro.to_string()
      quote do 10 |> Membrane.Time.milliseconds() end |> Macro.to_string()
      iex> 60_000_000 |> microseconds() |> to_code() |> Macro.to_string()
      quote do 1 |> Membrane.Time.minutes() end |> Macro.to_string()
      iex> 2 |> nanoseconds() |> to_code() |> Macro.to_string()
      quote do 2 |> #{inspect(__MODULE__)}.nanoseconds() end |> Macro.to_string()

  """
  @spec to_code(t) :: Macro.t()
  def to_code(time) when is_t(time) do
    {time, unit} = time |> best_unit()

    quote do
      unquote(time) |> unquote(__MODULE__).unquote(unit)()
    end
  end

  @doc """
  Returns string representation of result of `to_code/1`.
  """
  @spec pretty_duration(t) :: Macro.t()
  def to_code_str(time) when is_t(time) do
    time |> to_code() |> Macro.to_string()
  end

  @doc """
  Returns current time in pretty format (currently iso8601), as string
  Uses `system_time/0` under the hood.
  """
  @spec pretty_now :: String.t()
  def pretty_now do
    system_time() |> to_iso8601()
  end

  @doc """
  Returns current monotonic time based on `System.monotonic_time/0`
  in internal Membrane time units.

  Inlined by the compiler.
  """
  @spec monotonic_time() :: t
  def monotonic_time do
    System.monotonic_time() |> native_units
  end

  @doc """
  Returns current POSIX time of operating system
  in internal Membrane time units.

  Inlined by the compiler.
  """
  @spec os_time() :: t
  def os_time() do
    :os.system_time() |> native_units
  end

  @doc """
  Returns current Erlang VM system time based on `System.system_time/0`
  in internal Membrane time units.

  It is the VM view of the `os_time/0`. They may not match in case of time warps.
  It is not monotonic.

  Inlined by the compiler.
  """
  @spec vm_time() :: t
  def vm_time() do
    System.system_time() |> native_units
  end

  @doc """
  Returns current time of Erlang VM based on `System.system_time/0`
  in internal Membrane time units.

  Inlined by the compiler.
  """
  @deprecated "Use os_time/0 or vm_time/0 instead"
  @spec system_time() :: t
  def system_time do
    System.system_time() |> native_units
  end

  @doc """
  Converts `DateTime` to internal Membrane time units.

  Inlined by the compiler.
  """
  @spec from_datetime(DateTime.t()) :: t
  def from_datetime(value = %DateTime{}) do
    value |> DateTime.to_unix(:nanosecond) |> nanoseconds
  end

  @doc """
  Converts iso8601 string to internal Membrane time units.
  If `value` is invalid, throws match error.

  Inlined by the compiler.
  """
  @spec from_iso8601!(String.t()) :: t
  def from_iso8601!(value) when is_binary(value) do
    {:ok, datetime, _shift} = value |> DateTime.from_iso8601()
    datetime |> from_datetime
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
  @spec to_datetime(t) :: DateTime.t()
  def to_datetime(value) when is_t(value) do
    DateTime.from_unix!(value |> nanoseconds, :nanosecond)
  end

  @doc """
  Returns time as a iso8601 string.

  Inlined by the compiler.
  """
  @spec to_iso8601(t) :: String.t()
  def to_iso8601(value) when is_t(value) do
    value |> to_datetime |> DateTime.to_iso8601()
  end

  @doc """
  Returns time in system native units. Rounded using Kernel.round/1

  Inlined by the compiler.
  """
  @spec to_native_units(t) :: native_t
  def to_native_units(value) when is_t(value) do
    (value / (1 |> native_unit)) |> round
  end

  @doc """
  Returns time in nanoseconds. Rounded using Kernel.round/1

  Inlined by the compiler.
  """
  @spec to_nanoseconds(t) :: integer
  def to_nanoseconds(value) when is_t(value) do
    (value / (1 |> nanosecond)) |> round
  end

  @doc """
  Returns time in microseconds. Rounded using Kernel.round/1

  Inlined by the compiler.
  """
  @spec to_microseconds(t) :: integer
  def to_microseconds(value) when is_t(value) do
    (value / (1 |> microsecond)) |> round
  end

  @doc """
  Returns time in milliseconds. Rounded using Kernel.round/1

  Inlined by the compiler.
  """
  @spec to_milliseconds(t) :: integer
  def to_milliseconds(value) when is_t(value) do
    (value / (1 |> millisecond)) |> round
  end

  @doc """
  Returns time in seconds. Rounded using Kernel.round/1

  Inlined by the compiler.
  """
  @spec to_seconds(t) :: integer
  def to_seconds(value) when is_t(value) do
    (value / (1 |> second)) |> round
  end

  @doc """
  Returns time in minutes. Rounded using Kernel.round/1

  Inlined by the compiler.
  """
  @spec to_minutes(t) :: integer
  def to_minutes(value) when is_t(value) do
    (value / (1 |> minute)) |> round
  end

  @doc """
  Returns time in hours. Rounded using Kernel.round/1

  Inlined by the compiler.
  """
  @spec to_hours(t) :: integer
  def to_hours(value) when is_t(value) do
    (value / (1 |> hour)) |> round
  end

  @doc """
  Returns time in days. Rounded using Kernel.round/1

  Inlined by the compiler.
  """
  @spec to_days(t) :: integer
  def to_days(value) when is_t(value) do
    (value / (1 |> day)) |> round
  end

  @spec units() :: Keyword.t(t)
  defp units() do
    [
      days: 1 |> day(),
      hours: 1 |> hour(),
      minutes: 1 |> minute(),
      seconds: 1 |> second(),
      milliseconds: 1 |> millisecond(),
      microseconds: 1 |> microsecond(),
      nanoseconds: 1 |> nanosecond()
    ]
  end

  defp best_unit(time) do
    {unit, divisor} = units() |> Enum.find(fn {_unit, divisor} -> time |> rem(divisor) == 0 end)

    {time |> div(divisor), unit}
  end
end
