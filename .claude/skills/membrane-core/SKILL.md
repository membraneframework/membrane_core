---
name: membrane-core
description: Work with the Membrane multimedia streaming framework in Elixir. Use this skill whenever the user is building or debugging Membrane pipelines, writing custom Elements, Bins, or Filters, connecting pads, implementing callbacks, handling stream formats or EOS, or asking about Membrane architecture. Trigger on any mention of membrane_core, Membrane.Pipeline, Membrane.Element, Membrane.Bin, Membrane.Pad, or multimedia streaming in an Elixir context — even if the user doesn't say "Membrane" explicitly but is clearly working on this codebase.
---

# Membrane Framework

**Package**: `membrane_core` ~> 1.2 | **Docs**: https://hexdocs.pm/membrane_core/ | **Demos**: https://github.com/membraneframework/membrane_demo

## How to Approach Tasks

- **New component** — identify subtype (Source/Filter/Sink/Endpoint/Bin), define pads, implement required callbacks (`handle_buffer/4` for filters/sinks, `handle_demand/5` for manual-flow sources)
- **Generating boilerplate** — use `mix membrane.gen.filter MyApp.MyFilter`, `mix membrane.gen.source`, `mix membrane.gen.sink`, `mix membrane.gen.endpoint`, `mix membrane.gen.bin` instead of writing element skeletons by hand
- **Pipeline topology** — use the ChildrenSpec DSL (`child/2`, `get_child/1`, `via_in/2`, `via_out/2`)
- **Dynamic tracks** (demuxers, variable inputs) — use the Dynamic Pads Pattern below
- **Crash isolation** — group children with `{spec, group: :name, crash_group_mode: :temporary}`; handle recovery in `handle_crash_group_down/3`; see [Crash Groups guide](https://hexdocs.pm/membrane_core/crash_groups.md)
- **Debugging** — check pad `accepted_format` compatibility, lifecycle ordering (`handle_setup` vs `handle_playing`), flow control mode mismatches
- **Callback context** — every callback receives `ctx`; key fields: `ctx.children` (all current children), `ctx.pads` (pad states), `ctx.playback`; crash callbacks also carry `ctx.crash_initiator`, `ctx.exit_reason`, `ctx.group_name`; see `Membrane.Pipeline.CallbackContext`, `Membrane.Element.CallbackContext`
- **Full callback reference** — `references/callbacks.md`
- **Never modify code in `deps/`**
- **Use `mix hex.info <plugin name>` when you need to check the newest version of a plugin**
- **Search for appropriate plugins in `README.md`, in `all-packages` section**
- **Check input and output pad definitions of elements in `deps/` (use `cat <filename> | grep def_input_pad` and `cat <filename> | grep def_output pad`) to make sure output pad's `accepted_stream_format` is compatible with `accepted_stream_format` of the input pad which it is linked to.**
- **If the `accepted_stream_format` doesn't match, search for an element which can act as an adapter**

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
- **`accepted_format` matching syntax**: `_any` (accept anything) · `Membrane.RawAudio` (any struct of that type) · `%Membrane.RawAudio{channels: 2}` (match specific fields) · `%Membrane.RemoteStream{}` (unknown/unparsed stream)
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

All components spawned in the same `:spec` action enter `:playing` together (slowest setup wins). Elements and Bins wait for their parent before `handle_playing/2`.

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
| `Membrane.FilterAggregator` | Run multiple filters in a single process |
| `Membrane.Testing.Source` | Inject buffers into a pipeline in tests |
| `Membrane.Testing.Sink` | Capture and assert on buffers in tests |
| `Membrane.Debug.Filter` | Log/inspect buffers flowing through pipeline |
| `Membrane.Debug.Sink` | Log/inspect buffers at pipeline end |

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

All timestamps are `Membrane.Time.t()` (integer nanoseconds). Helpers: `Membrane.Time.seconds/1`, `Membrane.Time.milliseconds/1`, `Membrane.Time.microseconds/1`, etc. Timers started with `:start_timer` action fire `handle_tick/3`.

---

## Actions

Actions are returned from callbacks as `{[action_list], state}`.

```elixir
# Data (Elements only)
{:buffer, {pad_ref, %Membrane.Buffer{payload: binary, pts: pts, dts: dts, metadata: map}}}
{:stream_format, {pad_ref, %SomeFormat{}}}   # must be sent before the first buffer
{:event, {pad_ref, %SomeEvent{}}}            # can travel upstream or downstream
{:end_of_stream, pad_ref}

# Flow control
{:demand, {pad_ref, size}}        # manual input pad: request more data
{:redemand, pad_ref}              # re-evaluate demand on output pad
{:pause_auto_demand, pad_ref}     # auto input pad: pause pulling
{:resume_auto_demand, pad_ref}    # auto input pad: resume pulling

# Topology (Pipeline and Bin)
{:spec, children_spec}
{:remove_children, name_or_list}
{:remove_link, {child_name, pad_ref}}

# Communication
{:notify_parent, any_term}               # Element/Bin → parent; received in handle_child_notification/4
{:notify_child, {child_name, any_term}}  # Pipeline/Bin → child; received in handle_parent_notification/3

# Component control
{:setup, :complete | :incomplete}
{:terminate, reason}

# Timers
{:start_timer, {name, interval}}         # interval is Membrane.Time.t() nanoseconds
{:stop_timer, name}
{:timer_interval, {name, new_interval}}
```

---

## Key Source Files

| File | Purpose |
|------|---------|
| `lib/membrane/pipeline.ex` | Pipeline behaviour & all callbacks |
| `lib/membrane/bin.ex` | Bin behaviour & all callbacks |
| `lib/membrane/element/base.ex` | Shared element callbacks |
| `lib/membrane/element/with_input_pads.ex` | `handle_buffer/4`, `handle_stream_format/4`, `handle_end_of_stream/3` |
| `lib/membrane/element/with_output_pads.ex` | `handle_demand/5` |
| `lib/membrane/pad.ex` | Pad definitions, `Pad.ref/2` |
| `lib/membrane/buffer.ex` | Buffer struct |
| `lib/membrane/children_spec.ex` | Topology DSL |
| `lib/membrane/element/action.ex` | Action type specs |

---

## Callback Reference

See `references/callbacks.md`.
