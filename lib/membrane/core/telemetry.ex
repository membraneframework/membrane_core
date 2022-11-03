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
      Keyword.get(@telemetry_flags, :metrics, []) |> Enum.find(&(&1 == metric)) != nil
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
      Keyword.get(@telemetry_flags, :metrics, []) |> Enum.find(&(&1 == :bitrate)) != nil
    )
  end

  @doc false
  @spec __get_public_pad_name__(Membrane.Pad.ref_t()) :: Membrane.Pad.ref_t()
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

    report_event(event, value, Enum.find(@telemetry_flags, &(&1 == :links)) != nil)
  end

  @doc """
  Reports a pipeline/bin/element initialization.
  """
  defmacro report_init(type) when type in [:pipeline, :bin, :element] do
    event =
      quote do
        [:membrane, unquote(type), :init]
      end

    value =
      quote do
        %{path: ComponentPath.get_formatted()}
      end

    metadata =
      quote do
        %{log_metadata: Logger.metadata()}
      end

    report_event(
      event,
      value,
      Enum.find(@telemetry_flags, &(&1 == :inits_and_terminates)) != nil,
      metadata
    )
  end

  @doc """
  Reports a pipeline/bin/element termination.
  """
  defmacro report_terminate(type) when type in [:pipeline, :bin, :element] do
    event =
      quote do
        [:membrane, unquote(type), :terminate]
      end

    value =
      quote do
        %{path: ComponentPath.get_formatted()}
      end

    report_event(
      event,
      value,
      Enum.find(@telemetry_flags, &(&1 == :inits_and_terminates)) != nil
    )
  end

  # Conditional event reporting of telemetry events
  defp report_event(event_name, measurement, enable, metadata \\ nil) do
    if enable do
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
        fn ->
          _unused = unquote(event_name)
          _unused = unquote(measurement)
          _unused = unquote(metadata)
        end

        :ok
      end
    end
  end
end
