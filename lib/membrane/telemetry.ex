defmodule Membrane.Telemetry do
  @moduledoc """
  Defines basic telemetry event types used by Membrane's Core and reports them.
  Membrane uses [Telemetry Package](https://hex.pm/packages/telemetry) for instrumentation and does not store or save any measurements by itself.

  It is user's responsibility to use some sort of metrics reporter
  that will be attached to `:telemetry` package to consume and process generated measurements.

  ## Instrumentation
  `Membrane.Telemetry` publishes functions that return described below event names.

  The following events are published by Membrane's Core with following measurement types and metadata:

    * `[:membrane, :metric, :value]` - used to report metrics, such as input buffer's size inside functions, incoming events and received caps.
        * Measurement: `t:metric_event_value_t/0`
        * Metadata: `%{}`

    * `[:membrane, :link, :new]` - to report new link connection being initialized in pipeline.
        * Measurement: `t:new_link_event_value_t/0`
        * Metadata: `%{}`

  It also privides functions to report measurements. That measurements are reported only when application using Membrane Core specifies following in compile-time config file:

      config :membrane_core,
        enable_telemetry: true

  """

  alias Membrane.ComponentPath
  alias Membrane.Core.Parent.Link.Endpoint

  require Membrane.Pad

  @enable_telemetry Application.compile_env(:membrane_core, :enable_telemetry, false)

  @type event_name_t :: [atom(), ...]

  @typedoc """
  * component_path - element's or bin's path
  * metric - metric's name
  * value - metric's value
  """
  @type metric_event_value_t :: %{
          component_path: String.t(),
          metric: String.t(),
          value: integer()
        }

  @typedoc """
  * parent_path - process path of link's parent
  * from - from element name
  * to - to element name
  * pad_from - from's pad name
  * pad_to - to's pad name
  """
  @type new_link_event_value_t :: %{
          parent_path: String.t(),
          from: String.t(),
          to: String.t(),
          pad_from: String.t(),
          pad_to: String.t()
        }

  @doc """
  Macro for reporting metrics.

  Provided `calculate_measurement` is a function that calculates measurement.

  Metrics are reported only when it is enabled in the application using Membrane Core.
  """
  defmacro report_measurement(event_name, calculate_measurement) do
    if @enable_telemetry do
      quote do
        :telemetry.execute(
          unquote(event_name),
          unquote(calculate_measurement).(),
          %{}
        )
      end
    else
      # A hack to suppress the 'unused variable' warnings
      quote do
        fn ->
          _unused = unquote(event_name)
          _unused = unquote(calculate_measurement)
        end

        :ok
      end
    end
  end

  @doc """
  Reports metrics such as input buffer's size inside functions, incoming events and received caps.
  """
  @spec report_metric(String.t(), integer(), String.t()) :: :ok
  def report_metric(metric, value, log_tag) do
    calculate_measurement = get_calculate_measurement_function(metric, value, log_tag)

    report_measurement(
      [:membrane, :metric, :value],
      calculate_measurement
    )
  end

  @doc """
  Reports new link connection being initialized in pipeline.
  """
  @spec report_new_link(Endpoint.t(), Endpoint.t()) :: :ok
  def report_new_link(from, to) do
    calculate_measurement = get_calculate_measurement_function(from, to)

    report_measurement(
      [:membrane, :link, :new],
      calculate_measurement
    )
  end

  # Returns function to call inside `report_measurement` macro to prepare metric measurement.
  defp get_calculate_measurement_function(metric, value, log_tag) do
    fn ->
      component_path = ComponentPath.get_formatted() <> "/" <> (log_tag || "")

      %{
        component_path: component_path,
        metric: metric,
        value: value
      }
    end
  end

  # Returns function to call inside `report_measurement` macro to prepare new link measurement.
  defp get_calculate_measurement_function(from, to) do
    fn ->
      %Endpoint{child: from_child, pad_ref: from_pad} = from
      %Endpoint{child: to_child, pad_ref: to_pad} = to

      %{
        parent_path: Membrane.ComponentPath.get_formatted(),
        from: "#{inspect(from_child)}",
        to: "#{inspect(to_child)}",
        pad_from: "#{inspect(get_public_pad_name(from_pad))}",
        pad_to: "#{inspect(get_public_pad_name(to_pad))}"
      }
    end
  end

  defp get_public_pad_name(pad) do
    case pad do
      {:private, direction} -> direction
      {Membrane.Pad, {:private, direction}, ref} -> {Membrane.Pad, direction, ref}
      _pad -> pad
    end
  end
end
