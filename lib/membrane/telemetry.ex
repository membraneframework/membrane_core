defmodule Membrane.Telemetry do
  @moduledoc """
  Defines basic telemetry event types used by Membrane's Core.

  Membrane uses [Telemetry Package](https://hex.pm/packages/telemetry) for instrumentation and does not store or save any measurements by itself.

  It is user's responsibility to use some sort of metrics reporter
  that will be attached to `:telemetry` package to consume and process generated measurements.

  ## Instrumentation
  The following events are published by Membrane's Core with following measurement types and metadata:

    * `[:membrane, :element | :bin | :pipeline, handler, :start | :stop | :exception]` -
    where handler is any possible handle_* function defined for a component.
      * `:start` - when the handler begins execution
      * `:stop` - when the handler finishes execution
      * `:exception` - when the handler crashes during execution

    * `[:membrane, :metric, metric]` -
    where metric is any of the available metrics (see below)

  ## Enabling certain metrics/events
  A lot of events can happen hundreds times per second such as registering that a buffer has been sent/processed.

  This behaviour can come with a great performance penalties but may be helpful for certain discoveries. To avoid any runtime overhead
  when the reporting is not necessary all metrics/events are hidden behind a compile-time feature flags.
  To enable a particular measurement one must recompile membrane core with the following snippet put inside
  user's application `config.exs` file:

  ```
      config :membrane_core,
        telemetry_flags: [
          tracked_callbacks: [
            [:handle_setup, ...] | :all
          ]
        metrics: [:buffer, ...] | :all
        ]
    ```

  Available flags are (those are of a very low overhead):
  * `:links` - enables new links notifications
  * `:inits_and_terminates` - enables notifications of `init` and `terminate` events for elements/bins/pipelines


  Additionally one can control which metric values should get measured by passing an option of format :
  `metrics: [list of metrics]`

  # TODO revise possible metrics
  Available metrics are:
  * `:buffer` - number of buffers being sent from a particular element
  * `:bitrate` - total number of bits carried by the buffers mentioned above
  * `:queue_len` - number of messages in element's message queue during GenServer's `handle_info` invocation
  * `:stream_format` - indicates that given element has received new stream format, value always equals '1'
  * `:event` - indicates that given element has received a new event, value always equals '1'
  * `:store` - reports the current size of a input buffer when storing a new buffer
  * `:take_and_demand` - reports the current size of a input buffer when taking buffers and making a new demand
  """

  @type instrument :: :element | :bin | :pipeline
  @type event_name :: [atom() | list(atom())]

  @type element_state :: %{
          subprocess_supervisor: pid,
          terminating?: boolean(),
          setup_incomplete?: boolean(),
          effective_flow_control: EffectiveFlowController.effective_flow_control(),
          resource_guard: Membrane.ResourceGuard.t(),
          initialized?: boolean(),
          playback: Membrane.Playback.t(),
          module: module,
          type: Element.type(),
          name: Element.name(),
          internal_state: Element.state() | nil,
          pads_info: PadModel.pads_info() | nil,
          pads_data: PadModel.pads_data() | nil,
          parent_pid: pid
        }

  @type bin_state :: %{
          internal_state: Membrane.Bin.state() | nil,
          module: module,
          children: ChildrenModel.children(),
          subprocess_supervisor: pid(),
          name: Membrane.Bin.name() | nil,
          pads_info: PadModel.pads_info() | nil,
          pads_data: PadModel.pads_data() | nil,
          parent_pid: pid,
          links: %{Link.id() => Link.t()},
          crash_groups: %{CrashGroup.name() => CrashGroup.t()},
          children_log_metadata: Keyword.t(),
          playback: Membrane.Playback.t(),
          initialized?: boolean(),
          terminating?: boolean(),
          resource_guard: Membrane.ResourceGuard.t(),
          setup_incomplete?: boolean()
        }

  @type pipeline_state :: %{
          module: module,
          playback: Membrane.Playback.t(),
          internal_state: Membrane.Pipeline.state() | nil,
          children: ChildrenModel.children(),
          links: %{Link.id() => Link.t()},
          crash_groups: %{CrashGroup.name() => CrashGroup.t()},
          initialized?: boolean(),
          terminating?: boolean(),
          resource_guard: Membrane.ResourceGuard.t(),
          setup_incomplete?: boolean(),
          subprocess_supervisor: pid()
        }

  @typedoc """
  * component_path - element's or bin's path
  * metric - metric's name
  * value - metric's value
  """
  @type metric_event_value :: %{
          component_path: String.t(),
          metric: String.t(),
          value: integer()
        }

  @typedoc """
  * path - element's path
  """
  @type init_or_terminate_event_value :: %{
          path: Membrane.ComponentPath.path()
        }

  @typedoc """
  * parent_path - process path of link's parent
  * from - from element name
  * to - to element name
  * pad_from - from's pad name
  * pad_to - to's pad name
  """
  @type link_event_value :: %{
          parent_path: String.t(),
          from: String.t(),
          to: String.t(),
          pad_from: String.t(),
          pad_to: String.t()
        }
end
