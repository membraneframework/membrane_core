defmodule Membrane.Core.Telemetry do
  @moduledoc false

  alias Membrane.ComponentPath
  alias Membrane.Core.Parent.Link.Endpoint
  alias Membrane.Telemetry

  require Membrane.Pad

  @enable_telemetry Application.compile_env(:membrane_core, :enable_telemetry, false)

  @doc """
  Macro for reporting metrics.

  Metrics are reported only when it is enabled in the application using Membrane Core.
  """
  defmacro report_event(event_name, measurement) do
    if @enable_telemetry do
      quote do
        :telemetry.execute(
          unquote(event_name),
          unquote(measurement),
          %{}
        )
      end
    else
      # A hack to suppress the 'unused variable' warnings
      quote do
        fn ->
          _unused = unquote(event_name)
          _unused = unquote(measurement)
        end

        :ok
      end
    end
  end

  @doc """
  Reports metrics such as input buffer's size inside functions, incoming events and received caps.
  """
  @spec report_metric(atom(), integer(), String.t() | nil) :: :ok
  def report_metric(metric, value, log_tag \\ nil) do
    report_event(
      Telemetry.metric_event_name(),
      %{
        component_path: ComponentPath.get_formatted() <> "/" <> (log_tag || ""),
        metric: Atom.to_string(metric),
        value: value
      }
    )
  end

  @doc """
  Given list of buffers (or a single buffer) calculates total size of their payloads in bits
  and reports it.
  """
  @spec report_bitrate([Membrane.Buffer.t()] | Membrane.Buffer.t()) :: :ok
  def report_bitrate(buffers) do
    report_event(
      Telemetry.metric_event_name(),
      %{
        component_path: ComponentPath.get_formatted() <> "/",
        metric: "bitrate",
        value:
          8 * if is_list(buffers) do
            Enum.reduce(buffers, 0, &(Membrane.Payload.size(&1.payload) + &2))
          else
            Membrane.Payload.size(buffers.payload)
          end
      }
    )
  end

  @doc """
  Reports new link connection being initialized in pipeline.
  """
  @spec report_link(Endpoint.t(), Endpoint.t()) :: :ok
  def report_link(from, to) do
    report_event(
      Telemetry.new_link_event_name(),
      %{
        parent_path: Membrane.ComponentPath.get_formatted(),
        from: inspect(from.child),
        to: inspect(to.child),
        pad_from: get_public_pad_name(from.pad_ref) |> inspect(),
        pad_to: get_public_pad_name(to.pad_ref) |> inspect()
      }
    )
  end

  @spec report_init(:pipeline | :bin | :element) :: :ok
  def report_init(type) do
    report_event(
      case type do
        :pipeline -> Telemetry.pipeline_init_event_name()
        :bin -> Telemetry.bin_init_event_name()
        :element -> Telemetry.element_init_event_name()
      end,
      %{path: ComponentPath.get_formatted()}
    )
  end

  @spec report_terminate(:pipeline | :bin | :element) :: :ok
  def report_terminate(type) do
    report_event(
      case type do
        :pipeline -> Telemetry.pipeline_terminate_event_name()
        :bin -> Telemetry.bin_terminate_event_name()
        :element -> Telemetry.element_terminate_event_name()
      end,
      %{path: ComponentPath.get_formatted()}
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
