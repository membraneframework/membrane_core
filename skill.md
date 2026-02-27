# Membrane Framework Core — Skill Guide

## Project Overview

Membrane is a versatile multimedia streaming & processing framework written in **Elixir** (~> 1.17). It enables building media servers that can stream via WebRTC, RTSP, RTMP, HLS, HTTP; transcode/mix audio & video; handle dynamically connecting/disconnecting streams; and scale with Erlang fault-tolerance.

**Package**: `membrane_core` ~> 1.2
**Maintained by**: Software Mansion
**Docs**: https://hexdocs.pm/membrane_core/
**Demo projects**: https://github.com/membraneframework/membrane_demo

---

## Architecture

The framework has three component types. The key insight is that **Bin occupies two roles**: it acts as a *parent* (contains and manages children, like a Pipeline) and simultaneously as a *child* (can be placed inside a Pipeline or another Bin, just like an Element).

```
Pipeline
├── Element (Source/Filter/Sink/Endpoint)
├── Bin
│   ├── Element
│   └── Bin          ← bins nest arbitrarily deep
│       └── Element
└── ...
```

| Type | Role |
|------|------|
| **Pipeline** | Top-level orchestrator; parent only — cannot itself be a child |
| **Bin** | Both a parent (has children) and a child (has pads, receives parent notifications) |
| **Element** | Leaf node; child only — processes actual data |

### Element subtypes

| Subtype | Input pads | Output pads |
|---------|-----------|-------------|
| **Source** | — | yes |
| **Filter** | yes | yes |
| **Sink** | yes | — |
| **Endpoint** | yes | yes |

---

## Key Concepts

### Pads

Pads are the connection points between components. Data flows through linked pads.

**Pads are defined on Elements and Bins** (not Pipelines):

```elixir
def_input_pad :input, accepted_format: _any
def_output_pad :output, accepted_format: Membrane.RawAudio, flow_control: :auto
```

**Availability**:
- `:always` (static) — exactly one instance, referenced by atom name (e.g. `:input`, `:output`)
- `:on_request` (dynamic) — multiple instances, referenced via `Pad.ref(:name, id)`

**Flow control**:
- `:auto` — framework manages demand automatically (preferred for most filters/sinks)
- `:manual` — demand controlled explicitly via `:demand` / `:redemand` actions
- `:push` — producer sends without demand (risk of overflow)

**Rules**:
- One input pad ↔ one output pad only
- Pads must have compatible `accepted_format`
- Default pad names `:input`/`:output` allow omitting `via_in`/`via_out` in specs
- Pads of Bins are transparent: linking to a bin actually connects to an element inside it

### Buffers

The main data unit flowing through the pipeline:

```elixir
%Membrane.Buffer{
  payload: binary,              # actual media data
  pts: Membrane.Time.t() | nil, # presentation timestamp
  dts: Membrane.Time.t() | nil, # decode timestamp
  metadata: map | nil           # arbitrary extra info
}
```

### Stream Formats

Describe the type of data on a pad. Must be sent before the first buffer. Handled in `handle_stream_format/4`. Filter default implementation forwards it downstream.

### Events

Control messages that travel through pads. **Unique**: can travel both upstream and downstream (unlike buffers/stream formats/EOS). Handled in `handle_event/4`. Filter default implementation forwards them.

---

## Component Lifecycle

```
handle_init/2              # synchronous — blocks parent; spawn children, parse opts
  ↓
handle_setup/2             # async — heavy init (open files, connect to services)
  ↓                        # return {[setup: :incomplete], state} to delay :playing
handle_pad_added/3*        # called for dynamic pads linked in the same spec
  ↓
handle_playing/2           # component is ready — start sending/pulling data
  ↓
  [data processing / child management]
  ↓
handle_terminate_request/2 # default: {[terminate: :normal], state}
```

**Notes**:
- All components spawned in the **same `:spec`** action enter `:playing` simultaneously; if one's setup takes longer the others wait.
- `handle_pad_added/3` fires *before* `handle_playing/2` only when the dynamic pad is linked in **the same spec** that spawns the component. Pads linked in a **later spec** trigger `handle_pad_added/3` **after** `handle_playing/2` has already been called.
- Elements and Bins wait for their *parent* to enter `:playing` before they execute `handle_playing/2`.

---

## Callbacks

Components are divided by the two orthogonal roles they can hold: **parent** (has children) and **child** (has pads and a parent).

### Every component (Pipeline, Bin, Element)

| Callback | When called | Default |
|----------|-------------|---------|
| `handle_init/2` | Spawned (sync, blocks parent) | converts opts to map |
| `handle_setup/2` | After init (async) | no-op |
| `handle_playing/2` | Entering `:playing` | no-op |
| `handle_terminate_request/2` | Termination requested | `{[terminate: :normal], state}` |
| `handle_info/3` | Any non-Membrane Erlang message | logs warning |
| `handle_tick/3` | Timer tick (started with `:start_timer` action) | no-op |

### Parent components only (Pipeline and Bin)

| Callback | When called | Default |
|----------|-------------|---------|
| `handle_child_notification/4` | Child called `notify_parent` | no-op |
| `handle_child_setup_completed/3` | Child finished `handle_setup` | no-op |
| `handle_child_playing/3` | Child entered `:playing` | no-op |
| `handle_child_pad_removed/4` | Child removed a pad (child-initiated only) | no-op |
| `handle_child_terminated/3` | A child process terminated | no-op |
| `handle_crash_group_down/3` | All children in a crash group are down | no-op |
| `handle_element_start_of_stream/4` | A child element's pad started streaming | no-op |
| `handle_element_end_of_stream/4` | EOS received on a child element's input pad **or** sent on its output pad | no-op |

### Child components only (Bin and all Elements)

| Callback | When called | Default |
|----------|-------------|---------|
| `handle_parent_notification/3` | Parent sent a notification | no-op |
| `handle_pad_added/3` | Dynamic pad linked | no-op |
| `handle_pad_removed/3` | Dynamic pad unlinked | no-op |

### Pipeline only

| Callback | When called | Default |
|----------|-------------|---------|
| `handle_call/3` | Synchronous call from an external process | no-op |

### Elements with input pads (Filter, Sink, Endpoint)

| Callback | When called | Default |
|----------|-------------|---------|
| `handle_stream_format/4` | Stream format received on input pad | Filter: forwards downstream |
| `handle_start_of_stream/3` | First buffer about to arrive on input pad | no-op |
| `handle_buffer/4` | Buffer received on input pad | — (no default) |
| `handle_end_of_stream/3` | EOS received on element's own input pad | Filter: forwards downstream |

### Elements with output pads (Source, Filter, Endpoint)

| Callback | When called | Default |
|----------|-------------|---------|
| `handle_demand/5` | Downstream requested data on a `:manual` output pad | — (no default) |

### Events (all elements)

| Callback | When called | Default |
|----------|-------------|---------|
| `handle_event/4` | Event received on any pad | Filter: forwards; others: no-op |

---

## Actions

Actions are returned from callbacks as `{[action_list], state}`:

```elixir
# ── Data (elements only) ──────────────────────────────────────────────────────
{:buffer, {pad_ref, %Membrane.Buffer{...}}}    # send buffer on output pad
{:stream_format, {pad_ref, %SomeFormat{}}}     # send stream format on output pad
{:event, {pad_ref, %SomeEvent{}}}              # send event on any pad (up or downstream)
{:end_of_stream, pad_ref}                      # signal EOS on output pad

# ── Flow control ──────────────────────────────────────────────────────────────
# Manual input pads (flow_control: :manual) only:
{:demand, {pad_ref, size}}                     # request `size` more units from upstream
{:redemand, pad_ref}                           # re-evaluate demand on input pad

# Auto input pads (flow_control: :auto) only:
{:pause_auto_demand, pad_ref}                  # temporarily stop auto-pulling
{:resume_auto_demand, pad_ref}                 # resume auto-pulling

# ── Topology (Pipeline and Bin) ───────────────────────────────────────────────
{:spec, children_spec}                         # spawn and/or link children
{:remove_children, name_or_list}               # stop and remove children
{:remove_link, {child, pad_ref}}               # unlink a dynamic pad only

# ── Communication ─────────────────────────────────────────────────────────────
{:notify_parent, any_term}                     # send notification to parent (Bin + Elements)

# ── Component control ─────────────────────────────────────────────────────────
{:setup, :complete | :incomplete}              # control setup completion
{:terminate, reason}                           # stop this component

# ── Timers ────────────────────────────────────────────────────────────────────
{:start_timer, {name, interval}}               # start periodic timer → handle_tick/3
{:stop_timer, name}
{:timer_interval, {name, new_interval}}
```

---

## Pipeline & Bin DSL (ChildrenSpec)

```elixir
# Linear chain — child/2 spawns a new named child
child(:source, %Membrane.File.Source{location: "input.mp4"})
|> child(:demuxer, Membrane.MP4.Demuxer.ISOM)
|> child(:decoder, Membrane.H264.FFmpeg.Decoder)
|> child(:sink, %Membrane.File.Sink{location: "out.raw"})

# Explicit pad names (required for non-default names or dynamic pads)
get_child(:demuxer)
|> via_out(Pad.ref(:output, track_id))
|> via_in(:video_input)
|> child(:muxer, Membrane.MP4.Muxer.ISOM)

# get_child/1 links to an already-existing child
get_child(:existing_filter) |> child(:new_sink, Membrane.File.Sink)

# Bin boundary — inside a Bin definition
bin_input(:input) |> child(:filter, SomeFilter) |> bin_output(:output)

# Nesting a Bin inside a Pipeline (or another Bin) — same as any other child
child(:my_bin, MyBin) |> child(:sink, MySink)
```

---

## Dynamic Pads Pattern

The most common pattern for variable-track streams (e.g. MP4 demuxer):

```elixir
# 1. Spawn elements; demuxer has not yet identified tracks
def handle_init(_ctx, state) do
  spec = child(:source, Source) |> child(:demuxer, Demuxer)
  {[spec: spec], state}
end

# 2. Demuxer notifies parent once tracks are known
def handle_child_notification({:new_tracks, tracks}, :demuxer, _ctx, state) do
  spec = Enum.map(tracks, fn {id, _format} ->
    get_child(:demuxer)
    |> via_out(Pad.ref(:output, id))
    |> child({:decoder, id}, Decoder)
    |> child({:sink, id}, Sink)
  end)
  {[spec: spec], state}
end

# 3. Demuxer handles its newly created pad
def handle_pad_added(Pad.ref(:output, _id), _ctx, state) do
  {[], state}
end

# 4. React to pad removal (e.g. when a child is removed)
def handle_pad_removed(Pad.ref(:output, _id), _ctx, state) do
  {[], state}
end
```

---

## Built-in Utility Elements

| Module | Purpose |
|--------|---------|
| `Membrane.Funnel` | Multiple inputs → one output |
| `Membrane.Tee` | One input → multiple outputs |
| `Membrane.Connector` | Connect dynamic pads with internal buffering |
| `Membrane.FilterAggregator` | Run multiple filters in a single process |
| `Membrane.Testing.Source` | Test helper: inject buffers into a pipeline |
| `Membrane.Testing.Sink` | Test helper: capture and assert on buffers |

---

## Integration Patterns

### Static — always-on pipeline

```elixir
# application.ex
children = [
  %{
    id: Pipeline,
    start: {Membrane.Pipeline, :start_link, [MyPipeline, init_args]},
    restart: :transient
  }
]
Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
```

### Dynamic — per-user/per-request pipelines

```elixir
# application.ex — add a DynamicSupervisor
{DynamicSupervisor, strategy: :one_for_one, name: MyApp.PipelineSupervisor}

# Spawn on demand (e.g. in a LiveView mount)
{:ok, _sup} = DynamicSupervisor.start_child(
  MyApp.PipelineSupervisor,
  {Membrane.Pipeline, [MyPipeline, opts]}
)

# Tear down
DynamicSupervisor.terminate_child(MyApp.PipelineSupervisor, sup_pid)
```

### Batch — wait for pipeline to finish

```elixir
{:ok, _sup, pipeline_pid} = Membrane.Pipeline.start_link(TranscodePipeline, opts)
ref = Process.monitor(pipeline_pid)
receive do
  {:DOWN, ^ref, :process, ^pipeline_pid, :normal} -> :ok
end
```

---

## Timing

- All timestamps are `Membrane.Time.t()` (integer nanoseconds)
- Helpers: `Membrane.Time.seconds/1`, `Membrane.Time.milliseconds/1`, `Membrane.Time.microseconds/1`, etc.
- Timer actions → `handle_tick/3` callback
- Clock synchronization available via `:stream_sync` option in `ChildrenSpec`

---

## Testing

```elixir
import Membrane.ChildrenSpec
alias Membrane.Testing

spec = [
  child(:source, %Testing.Source{output: [<<1, 2, 3>>, <<4, 5, 6>>]})
  |> child(:sink, Testing.Sink)
]

pipeline = Testing.Pipeline.start_link_supervised!(spec: spec)

Testing.Assertions.assert_sink_buffer(pipeline, :sink, %Membrane.Buffer{payload: <<1, 2, 3>>})
```

---

## Demo Examples

The [`membraneframework/membrane_demo`](https://github.com/membraneframework/membrane_demo) monorepo contains runnable examples:

| Directory | What it demonstrates |
|-----------|---------------------|
| `simple_pipeline` | Minimal pipeline: HTTP → MP3 decode → speaker |
| `simple_element` | Writing a custom element (buffer counter) |
| `camera_to_hls` | Capture webcam and broadcast via HLS |
| `rtmp_to_hls` | Ingest RTMP, broadcast HLS |
| `rtmp_to_adaptive_hls` | Multi-bitrate adaptive HLS from RTMP |
| `rtsp_to_hls` | RTSP stream → HLS |
| `rtp` | Sending and receiving RTP/SRTP streams |
| `rtp_to_hls` | RTP input → HLS output |
| `webrtc_live_view` | WebRTC streaming with Phoenix LiveView |
| `mix_audio` | Audio mixing |

Livebook notebooks: `playing_mp3_file`, `audio_mixer`, `messages_source_and_sink`, `speech_to_text`, `openai_realtime_with_membrane_webrtc`.

---

## Key File Locations

| File | Purpose |
|------|---------|
| `lib/membrane/pipeline.ex` | Pipeline behaviour & all callbacks |
| `lib/membrane/bin.ex` | Bin behaviour & all callbacks |
| `lib/membrane/element/base.ex` | Shared element callbacks |
| `lib/membrane/element/with_input_pads.ex` | Input-side element callbacks |
| `lib/membrane/element/with_output_pads.ex` | `handle_demand/5` |
| `lib/membrane/pad.ex` | Pad definitions, `Pad.ref/2` |
| `lib/membrane/buffer.ex` | Buffer struct |
| `lib/membrane/children_spec.ex` | Topology DSL |
| `lib/membrane/element/action.ex` | Action type specs |
| `guides/useful_concepts/pads.md` | Pads deep-dive with examples |
| `guides/useful_concepts/components_lifecycle.md` | Lifecycle guide |
| `guides/useful_concepts/running_membrane_in_elixir_application.md` | Integration patterns |
