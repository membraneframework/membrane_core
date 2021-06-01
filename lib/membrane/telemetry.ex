defmodule Membrane.Telemetry do
  @moduledoc """
  Defines basic telemetry event types used by Membrane's Core.
  Membrane uses [Telemetry Package](https://hex.pm/packages/telemetry) for instrumentation and does not store or save any measurements by itself.

  It is user's responsibility to use some sort of metrics reporter
  that will be attached to `:telemetry` package to consume and process generated measurements.

  ## Instrumentation
  `Membrane.Telemetry` publishes functions that return described below event names.

  The following events are published by Membrane's Core with following measurement types and metadata:

    * `[:membrane, :metric, :value]` - used to report metrics, such as input buffer's size inside functions `Membrane.Core.InputBuffer.store/3` and `Membrane.Core.InputBuffer.take_and_demand/4`, incoming events in `Membrane.Core.Element.EventController` and received caps in `Membrane.Core.Element.CapsController`.
        * Measurement: `t:metric_event_value_t/0`
        * Metadata: `%{}`

    * `[:membrane, :link, :new]` - to report new link connection being initialized in pipeline.
        * Measurement: `t:new_link_event_value_t/0`
        * Metadata: `%{}`

  """

  @type event_name_t :: [atom(), ...]

  @typedoc """
  * element_path - element's process path with pad's name that input buffer is attached to
  * metric - metric name
  * value - metric's value

  """
  @type metric_event_value_t :: %{
          element_path: String.t(),
          metric: String.t(),
          value: integer()
        }

  @spec metric_event_name() :: event_name_t()
  def metric_event_name, do: [:membrane, :metric, :value]

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

  @spec new_link_event_name() :: event_name_t()
  def new_link_event_name, do: [:membrane, :link, :new]
end
