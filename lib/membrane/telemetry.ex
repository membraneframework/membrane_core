defmodule Membrane.Telemetry do
  @moduledoc """
  Defines basic telemetry event types used by Membrane's Core.

  Membrane uses [Telemetry Package](https://hex.pm/packages/telemetry) for instrumentation and does not store or save any measurements by itself.

  It is user's responsibility to use some sort of metrics reporter
  that will be attached to `:telemetry` package to consume and process generated measurements.

  ## Instrumentation
  The following events are published by Membrane's Core with following measurement types and metadata:

    * `[:membrane, :metric, :value]` - used to report metrics, such as input buffer's size inside functions, incoming events and received stream format
        * Measurement: `t:metric_event_value_t/0`
        * Metadata: `%{}`

    * `[:membrane, :link, :new]` - to report new link connection being initialized in pipeline.
        * Measurement: `t:link_event_value_t/0`
        * Metadata: `%{}`

    * `[:membrane, :pipeline | :bin | :element, :init]` - to report pipeline/element/bin initialization
        * Measurement: `t:init_or_terminate_event_value_t/0`
        * Metadata: `%{log_metadata: keyword()}`, includes Logger's metadata of created component

    * `[:membrane, :pipeline | :bin | :element, :terminate]` - to report pipeline/element/bin termination
        * Measurement: `t:init_or_terminate_event_value_t/0`
        * Metadata: `%{}`


  ## Enabling certain metrics/events
  A lot of events can happen literally hundreds times per second such as registering that a buffer has been sent/processed.

  This behaviour can come with a great performance penalties but may be helpful for certain discoveries. To avoid any runtime overhead
  when the reporting is not necessary all metrics/events are hidden behind a compile-time feature flags.
  To enable a particular measurement one must recompile membrane core with the following snippet put inside
  user's application `config.exs` file:

      config :membrane_core,
        telemetry_flags: [
          :flag_name,
          ...,
          {:metrics, [list of metrics]}
          ...
        ]

  Available flags are (those are of a very low overhead):
  * `:links` - enables new links notifications
  * `:inits_and_terminates` - enables notifications of `init` and `terminate` events for elements/bins/pipelines


  Additionally one can control which metric values should get measured by passing an option of format :
  `{:metrics, [list of metrics]}`

  Available metrics are:
  * `:buffer` - number of buffers being sent from a particular element
  * `:bitrate` - total number of bits carried by the buffers mentioned above
  * `:queue_len` - number of messages in element's message queue during GenServer's `handle_info` invocation
  * `:stream_format` - indicates that given element has received new stream format, value always equals '1'
  * `:event` - indicates that given element has received a new event, value always equals '1'
  * `:store` - reports the current size of a input buffer when storing a new buffer
  * `:take_and_demand` - reports the current size of a input buffer when taking buffers and making a new demand
  """

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
  * path - element's path
  """
  @type init_or_terminate_event_value_t :: %{
          path: Membrane.ComponentPath.path_t()
        }

  @typedoc """
  * parent_path - process path of link's parent
  * from - from element name
  * to - to element name
  * pad_from - from's pad name
  * pad_to - to's pad name
  """
  @type link_event_value_t :: %{
          parent_path: String.t(),
          from: String.t(),
          to: String.t(),
          pad_from: String.t(),
          pad_to: String.t()
        }
end
