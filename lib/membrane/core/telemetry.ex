defmodule Membrane.Core.Telemetry do
  @moduledoc false

  alias Membrane.ComponentPath
  alias Membrane.Core.Parent.Link.Endpoint
  alias Membrane.Telemetry

  require Membrane.Pad

  @enable_telemetry Application.compile_env(:membrane_core, :enable_telemetry, false)

  @doc """
  Macro for reporting metrics.

  Provided `calculate_measurement` is a function.

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
    calculate_measurement = fn ->
      component_path = ComponentPath.get_formatted() <> "/" <> (log_tag || "")

      %{
        component_path: component_path,
        metric: metric,
        value: value
      }
    end

    report_measurement(
      Telemetry.metric_event_name(),
      calculate_measurement
    )
  end

  @doc """
  Reports new link connection being initialized in pipeline.
  """
  @spec report_new_link(Endpoint.t(), Endpoint.t()) :: :ok
  def report_new_link(from, to) do
    calculate_measurement = fn ->
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

    report_measurement(
      Telemetry.new_link_event_name(),
      calculate_measurement
    )
  end

  defp get_public_pad_name(pad) do
    case pad do
      {:private, direction} -> direction
      {Membrane.Pad, {:private, direction}, ref} -> {Membrane.Pad, direction, ref}
      _pad -> pad
    end
  end
end
