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
            native_units: 1, native_unit: 0, nanoseconds: 1, nanosecond: 0, second: 0, seconds: 1}

  @type t :: integer
  @type non_neg_t :: non_neg_integer

  @units [
    %{plural: :days, singular: :day, abbrev: "d", duration: 86_400_000_000_000},
    %{plural: :hours, singular: :hour, abbrev: "h", duration: 3_600_000_000_000},
    %{plural: :minutes, singular: :minute, abbrev: "min", duration: 60_000_000_000},
    %{plural: :seconds, singular: :second, abbrev: "s", duration: 1_000_000_000},
    %{plural: :milliseconds, singular: :millisecond, abbrev: "ms", duration: 1_000_000},
    %{plural: :microseconds, singular: :microsecond, abbrev: "us", duration: 1_000},
    %{plural: :nanoseconds, singular: :nanosecond, abbrev: "ns", duration: 1}
  ]

  # Difference between 01.01.1900 (start of NTP epoch) and 01.01.1970 (start of Unix epoch) in seconds
  @ntp_unix_epoch_diff 2_208_988_800

  @two_to_pow_32 Ratio.pow(2, 32)

  @doc """
  Checks whether a value is `Membrane.Time.t`.
  """
  defguard is_time(value) when is_integer(value)

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
  def pretty_duration(time) when is_time(time) do
    {time, unit} = time |> best_unit()

    "#{time} #{unit.abbrev}"
  end

  @doc """
  Returns quoted code producing given amount time. Chosen unit is the biggest possible
  that doesn't involve precission loss.

  ## Examples

      iex> import #{inspect(__MODULE__)}
      iex> 10 |> milliseconds() |> to_code() |> Macro.to_string()
      quote do 10 |> #{inspect(__MODULE__)}.milliseconds() end |> Macro.to_string()
      iex> 60_000_000 |> microseconds() |> to_code() |> Macro.to_string()
      quote do #{inspect(__MODULE__)}.minute() end |> Macro.to_string()
      iex> 2 |> nanoseconds() |> to_code() |> Macro.to_string()
      quote do 2 |> #{inspect(__MODULE__)}.nanoseconds() end |> Macro.to_string()

  """
  @spec to_code(t) :: Macro.t()
  def to_code(time) when is_time(time) do
    case best_unit(time) do
      {1, unit} ->
        quote do
          unquote(__MODULE__).unquote(unit.singular)()
        end

      {time, unit} ->
        quote do
          unquote(time) |> unquote(__MODULE__).unquote(unit.plural)()
        end
    end
  end

  @doc """
  Returns string representation of result of `to_code/1`.
  """
  @spec inspect(t) :: String.t()
  def inspect(time) when is_time(time) do
    time |> to_code() |> Macro.to_string()
  end

  @doc """
  Returns current time in pretty format (currently iso8601), as string
  Uses `os_time/0` under the hood.
  """
  @spec pretty_now :: String.t()
  def pretty_now do
    os_time() |> to_iso8601()
  end

  @doc """
  Returns current monotonic time based on `System.monotonic_time/0`
  in `Membrane.Time` units.
  """
  @spec monotonic_time() :: t
  def monotonic_time do
    System.monotonic_time() |> native_units
  end

  @doc """
  Returns current POSIX time of operating system based on `System.os_time/0`
  in `Membrane.Time` units.

  This time is not monotonic.
  """
  @spec os_time() :: t
  def os_time() do
    System.os_time() |> native_units
  end

  @doc """
  Returns current Erlang VM system time based on `System.system_time/0`
  in `Membrane.Time` units.

  It is the VM view of the `os_time/0`. They may not match in case of time warps.
  It is not monotonic.
  """
  @spec vm_time() :: t
  def vm_time() do
    System.system_time() |> native_units
  end

  @doc """
  Converts iso8601 string to `Membrane.Time` units.
  If `value` is invalid, throws match error.
  """
  @spec from_iso8601!(String.t()) :: t
  def from_iso8601!(value) when is_binary(value) do
    {:ok, datetime, _shift} = value |> DateTime.from_iso8601()
    datetime |> from_datetime
  end

  @doc """
  Returns time as a iso8601 string.
  """
  @spec to_iso8601(t) :: String.t()
  def to_iso8601(value) when is_time(value) do
    value |> to_datetime |> DateTime.to_iso8601()
  end

  @doc """
  Converts `DateTime` to `Membrane.Time` units.
  """
  @spec from_datetime(DateTime.t()) :: t
  def from_datetime(%DateTime{} = value) do
    value |> DateTime.to_unix(:nanosecond) |> nanoseconds
  end

  @doc """
  Returns time as a `DateTime` struct. TimeZone is set to UTC.
  """
  @spec to_datetime(t) :: DateTime.t()
  def to_datetime(value) when is_time(value) do
    DateTime.from_unix!(value |> nanoseconds, :nanosecond)
  end

  @doc """
  Converts NTP timestamp (time since 0h on 1st Jan 1900) into Unix timestamp
  (time since 1st Jan 1970) represented in `Membrane.Time` units.

  NTP timestamp uses fixed point representation with the integer part in the first 32 bits
  and the fractional part in the last 32 bits.
  """
  @spec from_ntp_timestamp(ntp_time :: <<_::64>>) :: t()
  def from_ntp_timestamp(<<ntp_seconds::32, ntp_fraction::32>>) do
    fractional = (ntp_fraction * second()) |> div(@two_to_pow_32)

    unix_seconds = (ntp_seconds - @ntp_unix_epoch_diff) |> seconds()

    unix_seconds + fractional
  end

  @doc """
  Converts the timestamp into NTP timestamp. May introduce small rounding errors.
  """
  @spec to_ntp_timestamp(timestamp :: t()) :: <<_::64>>
  def to_ntp_timestamp(timestamp) do
    seconds = timestamp |> div(second())
    ntp_seconds = seconds + @ntp_unix_epoch_diff

    fractional = rem(timestamp, second())
    ntp_fractional = (fractional * @two_to_pow_32) |> div(second())

    <<ntp_seconds::32, ntp_fractional::32>>
  end

  @doc """
  Returns one VM native unit in `Membrane.Time` units.
  """
  @spec native_unit() :: t
  def native_unit() do
    native_units(1)
  end

  @doc """
  Returns given amount of VM native units in `Membrane.Time` units.
  """
  @spec native_units(integer) :: t
  def native_units(number) when is_integer(number) do
    number |> System.convert_time_unit(:native, :nanosecond) |> nanoseconds
  end

  @doc """
  Returns time in VM native units. Rounded using Kernel.round/1.
  """
  @spec to_native_units(t) :: integer
  def to_native_units(value) when is_time(value) do
    round(value / native_unit())
  end

  @doc """
  Returns timestamp in timebase units. Rounded to the nearest integer.

  ## Examples:
      iex> timestamp = 10 |> Membrane.Time.seconds()
      iex> timebase = Ratio.new(Membrane.Time.second(), 30)
      iex> Membrane.Time.round_to_timebase(timestamp, timebase)
      300
  """
  @spec round_to_timebase(number | Ratio.t(), number | Ratio.t()) :: integer
  def round_to_timebase(timestamp, timebase) do
    Ratio.new(timestamp, timebase) |> round_rational()
  end

  Enum.map(@units, fn unit ->
    @doc """
    Returns one #{unit.singular} in `#{inspect(__MODULE__)}` units.
    """
    @spec unquote(unit.singular)() :: t
    # credo:disable-for-next-line Credo.Check.Readability.Specs
    def unquote(unit.singular)() do
      unquote(unit.duration)
    end

    @doc """
    Returns given amount of #{unit.plural} in `#{inspect(__MODULE__)}` units.
    """
    @spec unquote(unit.plural)(integer | Ratio.t()) :: t
    # credo:disable-for-next-line Credo.Check.Readability.Specs
    def unquote(unit.plural)(number) when is_integer(number) do
      number * unquote(unit.duration)
    end

    # credo:disable-for-next-line Credo.Check.Readability.Specs
    def unquote(unit.plural)(number) do
      if not Ratio.is_rational?(number) do
        raise "Only integers and rationals can be converted with Membrane.Time.#{unquote(unit.plural)}"
      end

      Ratio.*(number, unquote(unit.duration))
      |> round_rational()
    end

    round_to_fun_name = :"round_to_#{unit.plural}"

    @doc """
    Returns time in #{unit.plural}. Rounded to the nearest integer.
    """
    @spec unquote(round_to_fun_name)(t) :: integer
    # credo:disable-for-next-line Credo.Check.Readability.Specs
    def unquote(round_to_fun_name)(time) when is_time(time) do
      Ratio.new(time, unquote(unit.duration)) |> round_rational()
    end

    as_fun_name = :"as_#{unit.plural}"

    @doc """
    Returns time in #{unit.plural}, represented as a rational number.
    """
    @spec unquote(as_fun_name)(t) :: integer | Ratio.t()
    # credo:disable-for-next-line Credo.Check.Readability.Specs
    def unquote(as_fun_name)(time) when is_time(time) do
      Ratio./(time, unquote(unit.duration))
    end
  end)

  defp best_unit(time) do
    unit = @units |> Enum.find(&(rem(time, &1.duration) == 0))
    {time |> div(unit.duration), unit}
  end

  defp round_rational(ratio) do
    ratio = make_rational(ratio)
    trunced = Ratio.trunc(ratio)

    if 2 * sign_of_rational(ratio) *
         Kernel.rem(ratio.numerator, ratio.denominator) >=
         ratio.denominator,
       do: trunced + sign_of_rational(ratio),
       else: trunced
  end

  defp make_rational(number) do
    if Ratio.is_rational?(number) do
      number
    else
      %Ratio{numerator: number, denominator: 1}
    end
  end

  defp sign_of_rational(ratio) do
    if ratio.numerator == 0, do: 0, else: Ratio.sign(ratio)
  end
end
