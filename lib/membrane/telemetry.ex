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

  It also privides macros to report metrics. Metrics are reported only when application using Membrane Core specifies following in compile-time config file:

      config :membrane_core,
        enable_metrics: true

  """

  @enable_metrics Application.compile_env(:membrane_core, :enable_metrics, false)

  @type event_name_t :: [atom(), ...]

  @typedoc """
  * element_path - element's process path with pad's name that input buffer is attached to
  * metric - metric's name
  * value - metric's value

  """
  @type metric_event_value_t :: %{
          element_path: String.t(),
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
  Macro for reporting metric measurements.

  Metrics are reported only when it is enabled in the application using Membrane Core.
  """
  defmacro report_metric(metric, value, log_tag) do
    if @enable_metrics do
      quote do
        alias Membrane.ComponentPath

        path = ComponentPath.get_formatted() <> "/" <> (unquote(log_tag) || "")

        :telemetry.execute(
          [:membrane, :metric, :value],
          %{
            element_path: path,
            metric: unquote(metric),
            value: unquote(value)
          },
          %{}
        )
      end
    else
      # A hack to suppress the 'unused variable' warnings
      quote do
        fn ->
          _unused = unquote(metric)
          _unused = unquote(value)
          _unused = unquote(log_tag)
        end

        :ok
      end
    end
  end

  @doc """
  Macro for reporting new links.

  Links are reported only when metrics reporting is enabled in the application using Membrane Core.
  """
  defmacro report_new_link(from, to) do
    if @enable_metrics do
      quote do
        alias Membrane.ComponentPath
        alias Membrane.Core.Parent.Link.Endpoint

        require Membrane.Pad

        get_public_pad_name = fn pad ->
          case pad do
            {:private, direction} -> direction
            {Membrane.Pad, {:private, direction}, ref} -> {Membrane.Pad, direction, ref}
            _pad -> pad
          end
        end

        %Endpoint{child: from_child, pad_ref: from_pad} = unquote(from)
        %Endpoint{child: to_child, pad_ref: to_pad} = unquote(to)

        :telemetry.execute(
          [:membrane, :link, :new],
          %{
            parent_path: Membrane.ComponentPath.get_formatted(),
            from: "#{inspect(from_child)}",
            to: "#{inspect(to_child)}",
            pad_from: "#{inspect(get_public_pad_name.(from_pad))}",
            pad_to: "#{inspect(get_public_pad_name.(to_pad))}"
          }
        )
      end
    else
      # A hack to suppress 'unused variable' warnings
      quote do
        fn ->
          _unused = unquote(from)
          _unused = unquote(to)
        end

        :ok
      end
    end
  end
end
