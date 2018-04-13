# Membrane Multimedia Framework: Core

This package provides core of the Membrane multimedia framework.


# Installation

Add the following line to your `deps` in `mix.exs`.  Run `mix deps.get`.

```elixir
{:membrane_core, git: "git@github.com:membraneframework/membrane-core.git"}
```

Then add the following line to your `applications` in `mix.exs`.

```elixir
:membrane_core
```

# Usage

Membrane Framework is an audio processing framework inspired by GStreamer[https://gstreamer.freedesktop.org/]. Workflow bases on setting up a pipeline, that consists of elements (sources producing stream, filters processing stream, and sinks consuming stream). Elements are linked using pads (sinks, through which they receive stream, and sources, through that they send stream forwards).

## Pipeline

To set up a pipeline you need to create a module, use Membrane.Pipeline, and implement handle_init/1 callback

```elixir
defmodule MyPipeline do
  use Membrane.Pipeline
  
  def handle_init(_args) do
    children = %{}
    links = %{}
    spec = %Pipeline.Spec{children: children, links: links}
    state = %{}
    {{:ok, spec}, state}
  end
end
```

Currently our Pipeline is valid, although empty. Let's add some elements:

```elixir
defmodule MyPipeline do
  use Membrane.Pipeline
  
  alias Membrane.Element.{File, Mad, PulseAudio}
  
  def handle_init(_args) do
    children = %{
      file_source: {File.Source, File.Source.Options{location: "my_file.mp3"}},
      decoder: Mad.Decoder,
      pulse_sink: {PulseAudio.Sink, PulseAudio.Sink.Options{ringbuffer_size_elements: 8192}},
    }
    links = %{
      {:file_source, :source} => {:mad, :sink},
      {:mad, :source} => {:pulse_sink, :sink}
    }
    spec = %Pipeline.Spec{children: children, links: links}
    state = %{}
    {{:ok, spec}, state}
  end
end
```

Above configuration will read mp3 audio from given file, decode it to raw samples and play through PulseAudio. As you see, current pipeline structure is linear, but Membrane allows to create and link elements with multiple sink and source pads, and link them together. Please note that each element has to be added to deps in mix.exs before using.

## Elements

Element is a single processing unit within pipeline. It works in a separate process, has its internal state, and communicates by message passing. It could be a source, filter or sink, which is determined by `use`d module from `Membrane.Element.Base`. Depending on that, it may supply different callbacks. Callbacks usually process some data or information, return actions, and update internal state. Therefore callback's return type is usually
```elixir
{{:ok, list_of_actions} | {:error, reason}, state}
```
One of a few exceptions from this rule is `handle_init/1` callback, that does not return actions, but only state, and is invoked on the startup of element. For callbacks for each element type see `Membrane.Element.Base.*` modules.

## Pads

Pads determine how elements are linked together. They are defined with `def_known_sink_pads/1` and `def_known_source_pads/1` macros. Arguments of those pads are maps in form of
```elixir
 %{pad_name => {availability, mode, accepted_caps}, ...}
```
where currently supported availability is :always, and modes are :pull or :push.

## Caps

Caps contain information about stream, eg. sample format, rate, and amount of channels for raw audio. They can be sent through sources with `caps: {source_pad, caps}` action. Sending caps that are not supported by sending or receiving pad (listed in `accepted_caps` in `def_known_sink/source_pads`) leads to an error. Receiving proper caps executes `handle_caps/4` callback. Default implementation forwards caps to all source pads (`forward: :all` action). Caps are always sent in order with buffers. Note that caps can arrive when element is in any of playback states.

## Events

Events are used to pass extra information between elements, and may have impact their pipeline behaviour. Eg. sending EOS event stops sender element and informs next about end of stream. Elements can be sent in buffer order like caps, but also through sinks. Receiving event invokes `handle_event/4` callback. Default implementation forwards event to all sink/source pads, basing on arrival pad type.

## Buffers

Buffers are structs containing payload and metadata. They are to be made by sources, processed by filters and consumed by sinks. Therefore incoming buffer implies executing handle_process/4 callback on filters and handle_write/4 on sinks. They are also `handle_process1/4` and `handle_write1/4` callbacks, accepting single buffer instead of list of buffers. Buffers can arrive only in `playing` playback state.

## Demands

As mentioned above, pads can work either in pull or push mode. Push mode means that each element just sends buffers forwards, no matter if the next element is able to handle them or not. This is OK if all elements are guaranteed to send as many buffers as their successors can handle. If not, mailboxes of such successors can be flood with huge amount of buffers, and terrible things can happen. That is where pull mode comes in. It bases on requesting demands: each element is guaranteed to receive at most as many buffers as it demanded. Demanding is done using :demand action, which has slightly different meaning in sinks and in filters.

### Demands in filters

Demands on filters sinks should be implied only by demands on sources. When demand incomes, `handle_demand/5` callback is executes. It typically returns demand action on some of sinks. Then, if they are any buffers accessible, `handle_process/4` is executed, and buffers are sent. If demand is underestimated, and there are still buffers accessible, and demand is not fully supplied, `handle_demand/5` is executed again. In opposite situation, if too many buffers are produced, they are also sent at once, but buffered in receivers sink buffer, until it demands more buffers. If there are not enough buffers to supply demand, all available buffers are supplied. When the next buffer incomes, demands on sources are checked, and if they are positive, `handle_demand/5` is also executed. Note that `handle_demand/5` callbacks `size` argument is always total demand of the source.

### Demands in sinks

Demands in sinks are implied by element itself. Unlike demands in filters, they are also accumulated. Eventual mechanisms of handling over/underestimated demands have to be implemented in element, as they are element-specific, and usually unnecessary.

### PullBuffer

To provide efficient and flexible soultion, demand system bases on PullBuffer, which is a buffer on each sink pad working in pull mode. At startup, PullBuffer requests demand of its `preferred_size`. Than, on demand, it returns demanded contents, and requests another demand, of size of taken buffers. This way it tries to maintain enough level of available buffers.
PullBuffer has also another parameter - `init_size`. Setting it prevents taking buffers from PullBuffer, until it reaches `init_size`. This can help preventing underruns, but also may cause delay, that is why it defaults to 0.
PullBuffer offers also a `toilet` mode. It is necessary when linking sources working in push mode to sinks in pull mode. Such sink sends buffers to PullBuffer without demand (pisses), and source just gets that buffer on demand (enables flush ;) Toilet mode has `warn` and `fail` levels, that when exceeded cause respectively emitting warning or stopping entire pipeline.
All PullBuffer options are configurable on pad link, for example:
```elixir
{:file_source, :source} => {:pulse_sink, :sink, pull_buffer: [preferred_size: 65535, init_size: 2048]}
```
or
```elixir
{:pulse_source, :source} => {:pulse_sink, :sink, pull_buffer: [toilet: [warn: 200_000, fail: 500_000]]}
```

### Sorts of demands
Currently supported are demands in bytes and buffers. Sort of demand is set in `def_known_sink_pads/1`, i.e.
```elixir
def_known_sink_pads %{sink: {:always, {:pull, demand_in: :bytes}, :any}}}
```

## Playback states

Both pipeline and element are always in one of playback states: :stopped, :prepared or :playing. Playback state always changes only one step at once in this order, and can be handled by `handle_prepare/2`, `handle_play/1` and `handle_stop/1` callbacks.


# Documentation (outdated :P)

Fetch the dependencies first:

```sh
mix deps.get
```

then you can generate documentation:

```sh
mix docs
```

HTML documentation will be built into `doc/` directory.


# Authors

* Marcin Lewandowski
* Mateusz Front

