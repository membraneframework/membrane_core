defmodule Membrane.Core.Telemetry do
  @moduledoc false

  alias Membrane.ComponentPath

  require Membrane.Pad

  @telemetry_flags Application.compile_env(:membrane_core, :telemetry_flags, [])

  @doc """
  Reports metrics such as input buffer's size inside functions, incoming events and received stream format.
  """
  defmacro report_metric(metric, value, log_tag \\ nil) do
    event =
      quote do
        [:membrane, :metric, :value]
      end

    value =
      quote do
        %{
          component_path: ComponentPath.get_formatted() <> "/" <> (unquote(log_tag) || ""),
          metric: Atom.to_string(unquote(metric)),
          value: unquote(value)
        }
      end

    report_event(
      event,
      value,
      Keyword.get(@telemetry_flags, :metrics, []) |> Enum.member?(metric)
    )
  end

  @doc """
  Given list of buffers (or a single buffer) calculates total size of their payloads in bits
  and reports it.
  """
  defmacro report_bitrate(buffers) do
    event =
      quote do
        [:membrane, :metric, :value]
      end

    value =
      quote do
        %{
          component_path: ComponentPath.get_formatted() <> "/",
          metric: "bitrate",
          value:
            8 *
              Enum.reduce(
                List.wrap(unquote(buffers)),
                0,
                &(Membrane.Payload.size(&1.payload) + &2)
              )
        }
      end

    report_event(
      event,
      value,
      Keyword.get(@telemetry_flags, :metrics, []) |> Enum.member?(:bitrate)
    )
  end

  @doc false
  @spec __get_public_pad_name__(Membrane.Pad.ref()) :: Membrane.Pad.ref()
  def __get_public_pad_name__(pad) do
    case pad do
      {:private, direction} -> direction
      {Membrane.Pad, {:private, direction}, ref} -> {Membrane.Pad, direction, ref}
      _pad -> pad
    end
  end

  @doc """
  Reports new link connection being initialized in pipeline.
  """
  defmacro report_link(from, to) do
    event =
      quote do
        [:membrane, :link, :new]
      end

    value =
      quote do
        %{
          parent_path: Membrane.ComponentPath.get_formatted(),
          from: inspect(unquote(from).child),
          to: inspect(unquote(to).child),
          pad_from:
            Membrane.Core.Telemetry.__get_public_pad_name__(unquote(from).pad_ref) |> inspect(),
          pad_to:
            Membrane.Core.Telemetry.__get_public_pad_name__(unquote(to).pad_ref) |> inspect()
        }
      end

    report_event(event, value, Enum.member?(@telemetry_flags, :links))
  end

  @doc """
  Reports a pipeline/bin/element initialization.
  """
  defmacro report_init(type) when type in [:pipeline, :bin, :element] do
    event = [:membrane, type, :init]

    value =
      quote do
        %{path: ComponentPath.get_formatted()}
      end

    metadata =
      quote do
        %{log_metadata: Logger.metadata()}
      end

    report_event(event, value, Enum.member?(@telemetry_flags, :inits_and_terminates), metadata)
  end

  defmacro report_span(type, subtype, do: block) do
    enabled = Enum.member?(@telemetry_flags, :spans)

    if enabled do
      quote do
        {time, val} =
          :timer.tc(fn ->
            unquote(block)
          end)

        path = ComponentPath.get()
        log_metadata = Logger.metadata()

        :telemetry.execute(
          [:membrane, unquote(type), :span, unquote(subtype)],
          %{time: time, time_unit: :microseconds, path: path},
          %{log_metadata: Logger.metadata()}
        )

        val
      end
    else
      block
    end
  end

  @doc """
  Reports a pipeline/bin/element termination.
  """
  defmacro report_terminate(type, path) when type in [:pipeline, :bin, :element] do
    event = [:membrane, type, :terminate]

    value =
      quote do
        %{path: unquote(path)}
      end

    report_event(event, value, Enum.member?(@telemetry_flags, :inits_and_terminates))
  end

  # Conditional event reporting of telemetry events
  defp report_event(event_name, measurement, enabled, metadata \\ nil) do
    if enabled do
      quote do
        :telemetry.execute(
          unquote(event_name),
          unquote(measurement),
          unquote(metadata) || %{}
        )
      end
    else
      # A hack to suppress the 'unused variable' warnings
      quote do
        _fn = fn ->
          _unused = unquote(event_name)
          _unused = unquote(measurement)
          _unused = unquote(metadata)
        end

        :ok
      end
    end
  end
end
