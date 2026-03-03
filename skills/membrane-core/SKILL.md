---
name: membrane-core
description: Work with the Membrane multimedia streaming framework in Elixir. Use this skill whenever the user is building or debugging Membrane pipelines, writing custom Elements, Bins, or Filters, connecting pads, implementing callbacks, handling stream formats or EOS, or asking about Membrane architecture. Trigger on any mention of membrane_core, Membrane.Pipeline, Membrane.Element, Membrane.Bin, Membrane.Pad, or multimedia streaming in an Elixir context — even if the user doesn't say "Membrane" explicitly but is clearly working on this codebase.
---

# Membrane Framework

**Package**: `membrane_core` ~> 1.2 | **Docs**: https://hexdocs.pm/membrane_core/ | **Demos**: https://github.com/membraneframework/membrane_demo

## How to Approach Tasks

- **New component** — identify subtype (Source/Filter/Sink/Endpoint/Bin), define pads, implement required callbacks (`handle_buffer/4` for filters/sinks, `handle_demand/5` for manual-flow sources)
- **Pipeline topology** — use the ChildrenSpec DSL (`child/2`, `get_child/1`, `via_in/2`, `via_out/2`); see Integration Patterns below or `references/integration.md`
- **Dynamic tracks** (demuxers, variable inputs) — use the Dynamic Pads Pattern below
- **Debugging** — check pad `accepted_format` compatibility, lifecycle ordering (`handle_setup` vs `handle_playing`), flow control mode mismatches
- **Full callback reference** — `references/callbacks.md`
- **Full actions reference** — `references/actions.md`
- **Never modify code in `deps/`**
- **Use `mix hex.info <plugin name>` when you need to check the newest version of a plugin**
- **Search for appropriate plugins in `README.md`, in `all-packages` section**
- **Check input and output pad definitions of elements in `deps/` to make sure output pad's `accepted_stream_format` is compatible with `accepted_stream_format` of the input pad which it is linked to.**
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

Element subtypes: **Source** (output only) · **Filter** (in + out) · **Sink** (input only) · **Endpoint** (in + out, stateful e.g. WebRTC)

---

## Pads

Defined on Elements and Bins (not Pipelines):

```elixir
def_input_pad :input, accepted_format: _any
def_output_pad :output, accepted_format: Membrane.RawAudio, flow_control: :auto
```

- **Availability**: `:always` (static, one instance, referenced by atom) or `:on_request` (dynamic, reference via `Pad.ref(:name, id)`)
- **Flow control**: `:auto` (framework manages demand — preferred), `:manual` (explicit via `:demand`/`:redemand`), `:push` (no demand, risk of overflow)
- One input pad ↔ one output pad only; pads must have compatible `accepted_format`
- Default pad names `:input`/`:output` allow omitting `via_in`/`via_out` in specs

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

# Inside a Bin
bin_input(:input) |> child(:filter, MyFilter) |> bin_output(:output)
```

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
```

---

## Timing

All timestamps are `Membrane.Time.t()` (integer nanoseconds). Helpers: `Membrane.Time.seconds/1`, `Membrane.Time.milliseconds/1`, `Membrane.Time.microseconds/1`, etc. Timers started with `:start_timer` action fire `handle_tick/3`.

---

## Reference Files

- `references/callbacks.md` — full callback tables for every component type
- `references/actions.md` — all actions with signatures and usage notes
- `references/integration.md` — integration patterns, demo examples, key source file locations
