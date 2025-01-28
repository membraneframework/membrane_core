defmodule Membrane.Telemetry do
  @moduledoc """
  Defines basic telemetry event types used by Membrane's Core.

  Membrane uses [Telemetry Package](https://hex.pm/packages/telemetry) for instrumentation and does not store or save any measurements by itself.

  It is user's responsibility to use some sort of event consumer and metric reporter
  that will be attached to `:telemetry` package to process generated measurements.

  ## Instrumentation
  The following events are published by Membrane's Core with following measurement types and metadata:

    * `[:membrane, :element | :bin | :pipeline, handler, :start | :stop | :exception]` -
    where handler is any possible handle_* function defined for a component.
      * `:start` - when the handler begins execution
      * `:stop` - when the handler finishes execution
      * `:exception` - when the handler crashes during execution

    * `[:membrane, :event, event_type]` -
    where event_type is any of the available event types (see below)

  ## Enabling specific events
  A lot of events can happen hundreds times per second such as registering that a buffer has been sent/processed.

  This behaviour can come with a great performance penalties but may be helpful for certain discoveries. To avoid any runtime overhead
  when the reporting is not necessary all events/events are hidden behind a compile-time feature flags.
  To enable a particular measurement one must recompile membrane core with the following config put inside
  user's application `config.exs` file:

  ```
      config :membrane_core,
        telemetry_flags: [
          tracked_callbacks: [
            [:handle_setup, ...] | :all
          ]
        events: [:buffer, ...] | :all
        ]
    ```

  Available events are:
  * `:link` - reports the number of links created in the pipeline
  * `:buffer` - number of buffers being sent from a particular element
  * `:queue_len` - number of messages in element's message queue during GenServer's `handle_info` invocation
  * `:stream_format` - indicates that given element has received new stream format, value always equals '1'
  * `:event` - indicates that given element has received a new event, value always equals '1'
  * `:store` - reports the current size of a input buffer when storing a new buffer
  """

  alias Membrane.{Bin, ComponentPath, Element, Pipeline, Playback, ResourceGuard}
  alias Membrane.Core.Child.PadModel
  alias Membrane.Core.Element.EffectiveFlowController
  alias Membrane.Core.Parent.{ChildrenModel, CrashGroup, Link}

  @typedoc """
  Types of telemetry events reported by Membrane Core
  """
  @type event_type :: :link | :buffer | :queue_len | :stream_format | :event | :store

  @typedoc """
  Atom representation of Membrane components subject to telemetry reports
  """
  @type component :: :element | :bin | :pipeline

  @typedoc """
  Component metadata included in each `t:callback_event_metadata/0`
  Internal state is gathered before and after each handler callback.
  State only represents component's state at the start of the callback
  """
  @type component_metadata :: %{
          component_state: element_state() | bin_state() | pipeline_state(),
          internal_state_after: Element.state() | Bin.state() | Pipeline.state(),
          internal_state_before: Element.state() | Bin.state() | Pipeline.state()
        }
  @typedoc """
  Metadata included with each telemetry component's handler profiled
  """
  @type callback_event_metadata :: %{
          callback: atom(),
          callback_args: [any()],
          component_metadata: component_metadata(),
          component_type: component()
        }

  @type element_state :: %{
          subprocess_supervisor: pid(),
          terminating?: boolean(),
          setup_incomplete?: boolean(),
          effective_flow_control: EffectiveFlowController.effective_flow_control(),
          resource_guard: ResourceGuard.t(),
          initialized?: boolean(),
          playback: Playback.t(),
          module: module(),
          type: Element.type(),
          name: Element.name(),
          internal_state: Element.state() | nil,
          pads_info: PadModel.pads_info() | nil,
          pads_data: PadModel.pads_data() | nil,
          parent_pid: pid()
        }

  @type bin_state :: %{
          internal_state: Bin.state() | nil,
          module: module(),
          children: ChildrenModel.children(),
          subprocess_supervisor: pid(),
          name: Bin.name() | nil,
          pads_info: PadModel.pads_info() | nil,
          pads_data: PadModel.pads_data() | nil,
          parent_pid: pid(),
          links: %{Link.id() => Link.t()},
          crash_groups: %{CrashGroup.name() => CrashGroup.t()},
          children_log_metadata: Keyword.t(),
          playback: Playback.t(),
          initialized?: boolean(),
          terminating?: boolean(),
          resource_guard: ResourceGuard.t(),
          setup_incomplete?: boolean()
        }

  @type pipeline_state :: %{
          module: module(),
          playback: Playback.t(),
          internal_state: Pipeline.state() | nil,
          children: ChildrenModel.children(),
          links: %{Link.id() => Link.t()},
          crash_groups: %{CrashGroup.name() => CrashGroup.t()},
          initialized?: boolean(),
          terminating?: boolean(),
          resource_guard: ResourceGuard.t(),
          setup_incomplete?: boolean(),
          subprocess_supervisor: pid()
        }

  @typedoc """
  Value of the specific event gathered
  """
  @type event_value :: %{
          value: map()
        }

  @typedoc """
  Metadata included with each telemetry event
  """
  @type event_metadata :: %{
          event: event_type(),
          component_path: ComponentPath.path(),
          component_metadata: any()
        }

  @typedoc """
  Value of the link event
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
  @type buffer_event_value :: integer()
  @type queue_len_event_value :: integer()
  @type stream_format_event_value :: %{format: map(), pad_ref: String.t()}
  @type incoming_event_value :: String.t()
  @type store_event_value :: %{value: integer(), log_tag: String.t()}

  @doc """
  Returns if the event type is configured to be gathered by Membrane's Core telemetry
  """
  @spec event_gathered?(any()) :: boolean()
  defdelegate event_gathered?(event_type), to: Membrane.Core.Telemetry

  @doc """
  Lists all components and their callbacks tracked by Membrane's Core telemetry
  """
  @spec tracked_callbacks() :: [
          {:bin, [atom(), ...]} | {:element, [atom(), ...]} | {:pipeline, [atom(), ...]},
          ...
        ]
  defdelegate tracked_callbacks, to: Membrane.Core.Telemetry

  @doc """
  Lists all possible components and their callbacks that can be gathered when telemetry is enabled
  """
  @spec tracked_callbacks_available() :: [
          {:bin, [atom(), ...]} | {:element, [atom(), ...]} | {:pipeline, [atom(), ...]},
          ...
        ]
  defdelegate tracked_callbacks_available, to: Membrane.Core.Telemetry
end
