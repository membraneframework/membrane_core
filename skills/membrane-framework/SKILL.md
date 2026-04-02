---
name: membrane-framework
description: Work with the Membrane multimedia streaming framework in Elixir. Use this skill whenever the user is building or debugging Membrane pipelines, writing custom Elements, Bins, or Filters, connecting pads, implementing callbacks, handling stream formats or EOS, or asking about Membrane architecture. Trigger on any mention of membrane_core, membrane, membrane framework, Membrane.Pipeline, Membrane.Sink, Membrane.Source, Membrane.Filter, Membrane.Endpoint, Membrane.Bin, Membrane.Pad, or multimedia streaming in an Elixir context — even if the user doesn't say "Membrane" explicitly but is clearly working on this codebase.
---

# Membrane Framework

**Package**: `membrane_core` ~> 1.2 | **Docs**: https://hexdocs.pm/membrane_core/ | **Module index**: https://hexdocs.pm/membrane_core/llms.txt | **Demos**: https://github.com/membraneframework/membrane_demo | **All packages**: [packages_list.md](../../guides/llms/packages_list.md)

## How to Approach Tasks

- **New component** — before writing a new element, check [packages_list.md](../../guides/llms/packages_list.md) to see if it already exists in an existing plugin; if not, identify subtype (Source/Filter/Sink/Endpoint/Bin), define pads, implement required callbacks (`handle_buffer/4` for filters/sinks, `handle_demand/5` for manual-flow sources)
- **Generating boilerplate** — use `mix membrane.gen.filter MyApp.MyFilter`, `mix membrane.gen.source`, `mix membrane.gen.sink`, `mix membrane.gen.endpoint`, `mix membrane.gen.bin` instead of writing component skeletons by hand
- **Choosing element subtype** — prefer `Filter` for transformations (has sensible defaults for stream_format forwarding); use `Endpoint` only when output is unrelated to input (e.g. a UDP Endpoint); use `Source`/`Sink` for pure producers/consumers
- **Flow control** — default to `:auto` on all pads; only use `:manual` when you need fine-grained backpressure control; Almost the only use case of `:push` are output pads of Sources/Endpoints that cannot control when they produce data, e.g. UDP Source/Endpoint.
- **Pipeline topology** — use the ChildrenSpec DSL (`child/2`, `get_child/1`, `via_in/2`, `via_out/2`) (more info: [Membrane.ChildrenSpec](https://hexdocs.pm/membrane_core/Membrane.ChildrenSpec.md))
- **Static vs dynamic topology** — return `spec:` from `handle_init/2` for static pipelines; return additional `spec:` actions from any callback (e.g. `handle_child_notification/4`) to grow the topology at runtime
- **Naming children** — use atoms (`:source`) for singletons, tuples (`{:decoder, track_id}`) for multi-instance children of the same type
- **Detecting pipeline completion** — implement `handle_element_end_of_stream/4` in the pipeline to know when a sink's input pad received EOS; then return `{[terminate: :normal], state}` (doesn't work if sink is a Membrane.Bin - then expect a custom message from the bin in `handle_child_notification` callback instead, if the bin sends it)
- **Dynamic tracks** (demuxers, variable inputs) — use the Dynamic Pads Pattern below
- **Crash isolation** — group children with `{spec, group: <name>, crash_group_mode: :temporary}`; handle recovery in `handle_crash_group_down/3`; see [Crash Groups guide](https://hexdocs.pm/membrane_core/crash_groups.md)
- **Inserting debug probes** — add `child(:probe, %Membrane.Debug.Filter{handle_buffer: &IO.inspect(&1, label: :buffer)})` between any two elements to log buffers without changing pipeline logic. You can use different logging functions than `IO.inspect/2`. More info: [Membrane.Debug.Filter](https://hexdocs.pm/membrane_core/Membrane.Debug.Filter.md).
- **Linking children** - linked children pads accepted formats must have non-empty intersections
- **Debugging** — check pad `accepted_format` compatibility
- **Callback context** — every callback receives `ctx`; key fields: `ctx.children`, `ctx.pads`, `ctx.playback`; crash callbacks also have `ctx.crash_initiator`, `ctx.exit_reason`, `ctx.group_name`; see [Pipeline.CallbackContext](https://hexdocs.pm/membrane_core/Membrane.Pipeline.CallbackContext.md), [Bin.CallbackContext](https://hexdocs.pm/membrane_core/Membrane.Bin.CallbackContext.md), [Element.CallbackContext](https://hexdocs.pm/membrane_core/Membrane.Element.CallbackContext.md)

- **Logging** — use `Membrane.Logger` instead of `Logger` in Membrane components; it prepends component context to log messages. Requires `use Membrane.Logger` in the module before calling any logging functions.
- **Never modify code in `deps/`**
- **Use `mix hex.info <plugin name>` when you need to check the newest version of a plugin**
- **Search for appropriate plugins in `README.md`, in `all-packages` section**
- **Check input and output pad definitions of elements in `deps/` (use `cat <filename> | grep def_input_pad` and `cat <filename> | grep def_output pad`) to make sure output pad's `accepted_stream_format` is compatible with `accepted_stream_format` of the input pad which it is linked to.**
- **If the `accepted_stream_format` doesn't match, search for an element which can act as an adapter**
- **When constructing Membrane Pipeline, lean towards using most powerful Membrane Components, which are [Boombox.Bin](https://hexdocs.pm/boombox/llms.txt) and [Membrane.Transcoder](https://hexdocs.pm/membrane_transcoder_plugin/llms.txt), instead of using many smaller plugins**

---

## Common Pitfalls

- **Modifying code in `deps/` directory** - never do that
- **Using `child/2` for an already-spawned child** — `child/2` always spawns a new process; use `get_child/1` to reference an existing one; duplicating a name raises an error
- **Linking static pads outside the spawning spec** — static pads must be linked in the same `spec` that spawns the component; linking them later raises a `LinkError`
- **Not wiring a dynamic bin pad in `handle_pad_added/3`** — a dynamic bin input pad must be connected to an internal child within 5 seconds or a `LinkError` is raised
- **Heavy work in `handle_init/2`** — `handle_init` is synchronous and blocks the parent; move file I/O, network connections, etc. to `handle_setup/2`
- **Producing data before `handle_playing/2`** — pads are not ready until `:playing`; don't send buffers from `handle_setup/2`
- **Using `:push` flow control carelessly** — whenever it is possible use `:auto` instead (eventually `:manual`). Source/Endpoint output pads are the exception.
- **Returning non-spec actions from `handle_init/2`** — we recommend to return only `:spec` action from this callback.

---

## Architecture

```
Pipeline
├── Element (Source/Filter/Sink/Endpoint)  ← leaf, processes data
├── Bin                                     ← dual role: parent (has children) + child (has pads)
│   ├── Element
│   └── Bin                                ← bins nest arbitrarily deep
└── ...
```

| Type | Parent | Child | Has Pads |
|------|--------|-------|----------|
| **Pipeline** | yes | no | no |
| **Bin** | yes | yes | yes |
| **Element** | no | yes | yes |

Element subtypes: **Source** (output only) · **Filter** (in + out, output is transformed input) · **Sink** (input only) · **Endpoint** (in + out, but output might be not related to input)

---

## Pads

Defined on Elements and Bins (not Pipelines) using `def_input_pad/2` (`Membrane.Element.WithInputPads`) and `def_output_pad/2` (`Membrane.Element.WithOutputPads`):

```elixir
def_input_pad :input, accepted_format: _any
def_output_pad :output, accepted_format: Membrane.RawAudio, flow_control: :auto
```

- **Availability**: `:always` (static, one instance, referenced by atom) or `:on_request` (dynamic, reference via `Pad.ref(:name, id)`)
- **Flow control**: `:auto` (framework manages demand — preferred), `:manual` (explicit via `:demand`/`:redemand`), `:push` (no demand, risk of overflow)
- One input pad ↔ one output pad only; pads must have compatible `accepted_format`
- Default pad names `:input`/`:output` allow omitting `via_in`/`via_out` in specs
- **`accepted_format` matching syntax**: `_any` (accept anything) · `Membrane.RawAudio` (any struct of that type) · `%Membrane.RawAudio{channels: 2}` (match specific fields) · `%Membrane.RemoteStream{}` (unknown/unparsed stream). `any_of(patter1, pattern2, ...)` matches if any pattern matches. 
- **Full pads guide** (static vs dynamic, bin pads, lifecycle): [Everything about pads](https://hexdocs.pm/membrane_core/pads.md)

---

## Component Lifecycle

```
handle_init/2      sync, blocks parent — parse opts, return initial spec
handle_setup/2     async — heavy init (open files, connect services)
                   return {[setup: :incomplete], state} to delay :playing
handle_pad_added/3 fires for dynamic pads linked in the same spec
handle_playing/2   component is ready — start producing/consuming data
```

All components spawned in the same `:spec` action enter `:playing` together (they synchronize to the slowest setup). Elements and Bins wait for their parent before `handle_playing/2`.

**Stream format and EOS rules (critical for filter authors):**
- A source/filter **must send `{:stream_format, {pad, format}}` before the first buffer** on each output pad, or downstream elements crash
- The default [`handle_stream_format/4`](https://hexdocs.pm/membrane_core/Membrane.Element.WithInputPads.md) in filters forwards the format downstream — if you override it, you must forward manually or return the `{:stream_format, ...}` action yourself
- The default [`handle_end_of_stream/3`](https://hexdocs.pm/membrane_core/Membrane.Element.WithInputPads.md) in filters forwards EOS downstream — overriding without forwarding will stall the pipeline

Full lifecycle guide: [Lifecycle of Membrane Components](https://hexdocs.pm/membrane_core/components_lifecycle.md)

---

## Pipeline & Bin DSL (ChildrenSpec)

```elixir
# Linear chain — child/2 spawns a new named child
child(:source, %Membrane.File.Source{location: "input.mp4"})
|> child(:filter, MyFilter)
|> child(:sink, %Membrane.File.Sink{location: "out.raw"})

# Explicit pad names (required for non-default names or dynamic pads)
get_child(:demuxer)
|> via_out(Pad.ref(:output, track_id))
|> via_in(:video_input)
|> child(:decoder, Membrane.H264.FFmpeg.Decoder)

# Link to an already-existing child
get_child(:existing_filter) |> child(:new_sink, MySink)

# Inside a Bin — bin_input/bin_output connect the bin's own pads to internal children
bin_input(:input) |> child(:filter, MyFilter) |> bin_output(:output)

# Crash group — all children in the spec share the group; a crash in any terminates all
{child(:source, Source) |> child(:sink, Sink), group: :my_group, crash_group_mode: :temporary}
```

**Bin pad wiring rules:**
- `bin_input(pad_ref)` / `bin_output(pad_ref)` are the interior side of the bin's own pads
- Dynamic bin input pads **must** be wired inside `handle_pad_added/3` within 5 seconds or a `LinkError` is raised
- Linking to a bin actually links directly to the inner component (no extra message hop)

---

## Dynamic Pads Pattern

The standard approach for variable-track streams (e.g. MP4 demuxers):

```elixir
# 1. Spawn source + demuxer; demuxer hasn't identified tracks yet
def handle_init(_ctx, state) do
  {[spec: child(:source, Source) |> child(:demuxer, Demuxer)], state}
end

# 2. Demuxer notifies parent once tracks are known
def handle_child_notification({:new_tracks, tracks}, :demuxer, _ctx, state) do
  spec = Enum.map(tracks, fn {id, _fmt} ->
    get_child(:demuxer)
    |> via_out(Pad.ref(:output, id))
    |> child({:decoder, id}, Decoder)
    |> child({:sink, id}, Sink)
  end)
  {[spec: spec], state}
end
```

---

## Built-in Utility Elements

| Module | Purpose |
|--------|---------|
| `Membrane.Funnel` | Multiple inputs → one output |
| `Membrane.Tee` | One input → multiple outputs |
| `Membrane.Connector` | Connect dynamic pads with internal buffering |
| `Membrane.Testing.Source` | Inject buffers into a pipeline in tests |
| `Membrane.Testing.Sink` | Capture and assert on buffers in tests |
| `Membrane.Debug.Filter` | Log/inspect buffers flowing through pipeline |
| `Membrane.Debug.Sink` | Log/inspect buffers at pipeline end |
| `Membrane.FilterAggregator` | It is deprecated, just don't use it |

---

## Testing

```elixir
import Membrane.ChildrenSpec
import Membrane.Testing.Assertions
alias Membrane.Testing

pipeline = Testing.Pipeline.start_link_supervised!(spec: [
  child(:source, %Testing.Source{output: [<<1, 2, 3>>, <<4, 5, 6>>]})
  |> child(:sink, Testing.Sink)
])

assert_sink_buffer(pipeline, :sink, %Membrane.Buffer{payload: <<1, 2, 3>>})
assert_start_of_stream(pipeline, :sink)
assert_end_of_stream(pipeline, :sink)
```

- `Testing.DynamicSource` — like `Testing.Source` but with a dynamic output pad

---

## Timing

All timestamps are `Membrane.Time.t()`. It is integer nanoseconds under the hood, but don't use this information, because it is a part of the private API. However, keep in mind you can perform operations on `Membrane.Time.t()` using `+` or `-` operators. Helpers: `Membrane.Time.seconds/1`, `Membrane.Time.milliseconds/1`, `Membrane.Time.microseconds/1`, etc. Timers started with `:start_timer` action fire `handle_tick/3`.

More info: [Membrane.Time](https://hexdocs.pm/membrane_core/Membrane.Time.md), [Timestamps guide](https://hexdocs.pm/membrane_core/timestamps.md).

---

## Actions

Actions are returned from callbacks as `{[action_list], state}`. Full reference by component type:

- [Membrane.Element.Action](https://hexdocs.pm/membrane_core/Membrane.Element.Action.md) — buffers, stream_format, events, EOS, demand, timers, notify_parent, setup, terminate
- [Membrane.Bin.Action](https://hexdocs.pm/membrane_core/Membrane.Bin.Action.md) — spec, remove_children, remove_link, notify_parent, notify_child, timers, setup, terminate
- [Membrane.Pipeline.Action](https://hexdocs.pm/membrane_core/Membrane.Pipeline.Action.md) — spec, remove_children, remove_link, notify_child, timers, terminate

---

## Key Source Files

| Module | Purpose |
|--------|---------|
| [`Membrane.Pipeline`](https://hexdocs.pm/membrane_core/Membrane.Pipeline.md) | Pipeline behaviour & all callbacks |
| [`Membrane.Pipeline.Action`](https://hexdocs.pm/membrane_core/Membrane.Pipeline.Action.md) | Pipeline action type specs |
| [`Membrane.Bin`](https://hexdocs.pm/membrane_core/Membrane.Bin.md) | Bin behaviour & all callbacks |
| [`Membrane.Bin.Action`](https://hexdocs.pm/membrane_core/Membrane.Bin.Action.md) | Bin action type specs |
| [`Membrane.Element.Base`](https://hexdocs.pm/membrane_core/Membrane.Element.Base.md) | Shared element callbacks |
| [`Membrane.Element.WithInputPads`](https://hexdocs.pm/membrane_core/Membrane.Element.WithInputPads.md) | `handle_buffer/4`, `handle_stream_format/4`, `handle_end_of_stream/3` |
| [`Membrane.Element.WithOutputPads`](https://hexdocs.pm/membrane_core/Membrane.Element.WithOutputPads.md) | `handle_demand/5` |
| [`Membrane.Element.Action`](https://hexdocs.pm/membrane_core/Membrane.Element.Action.md) | Element action type specs |
| [`Membrane.Pad`](https://hexdocs.pm/membrane_core/Membrane.Pad.md) | Pad definitions, `Pad.ref/2` |
| [`Membrane.Buffer`](https://hexdocs.pm/membrane_core/Membrane.Buffer.md) | Buffer struct |
| [`Membrane.ChildrenSpec`](https://hexdocs.pm/membrane_core/Membrane.ChildrenSpec.md) | Topology DSL |

---

## Callback Reference

Callbacks are documented in the relevant behaviour modules:

- [Membrane.Pipeline](https://hexdocs.pm/membrane_core/Membrane.Pipeline.md) — `handle_init`, `handle_setup`, `handle_playing`, `handle_call`, `handle_child_notification`, `handle_child_terminated`, `handle_crash_group_down`, `handle_element_end_of_stream`, etc.
- [Membrane.Bin](https://hexdocs.pm/membrane_core/Membrane.Bin.md) — same as Pipeline plus `handle_pad_added`, `handle_pad_removed`, `handle_parent_notification`
- [Membrane.Element.Base](https://hexdocs.pm/membrane_core/Membrane.Element.Base.md) — callbacks common to all elements: `handle_init`, `handle_setup`, `handle_playing`, `handle_pad_added`, `handle_pad_removed`, `handle_parent_notification`, `handle_info`, `handle_tick`
- [Membrane.Element.WithInputPads](https://hexdocs.pm/membrane_core/Membrane.Element.WithInputPads.md) — `handle_buffer`, `handle_stream_format`, `handle_start_of_stream`, `handle_end_of_stream`
- [Membrane.Element.WithOutputPads](https://hexdocs.pm/membrane_core/Membrane.Element.WithOutputPads.md) — `handle_demand`
- [Membrane.Source](https://hexdocs.pm/membrane_core/Membrane.Source.md), [Membrane.Filter](https://hexdocs.pm/membrane_core/Membrane.Filter.md), [Membrane.Sink](https://hexdocs.pm/membrane_core/Membrane.Sink.md), [Membrane.Endpoint](https://hexdocs.pm/membrane_core/Membrane.Endpoint.md) — combine the above with default implementations
