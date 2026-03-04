# Manual demands

Elements that use `:manual` flow control are responsible for explicitly
requesting data from their input pads. This guide explains how that mechanism
works and how to choose the right demand unit for your use case.

## How manual flow control works

When an input pad has `flow_control: :manual`, the element controls exactly
how much data it wants to receive on that pad at any given time. Each such
pad has an internal input queue that manages buffering and flow.

The general flow for a filter with a manual input and output looks like this:

1. **At startup**, the input queue issues an initial demand upstream to
   pre-fill itself to its target size. This happens automatically before the
   element returns its first `:demand` action, so that data is already
   available when the element first asks for it.

2. **When downstream demands data** (via `handle_demand/5`), the element
   requests some amount from its input queue using the
   [`:demand`](`t:Membrane.Element.Action.demand/0`) action.

3. **The queue delivers those buffers** synchronously from what it has
   buffered, invoking
   [`handle_buffer/4`](`c:Membrane.Element.WithInputPads.handle_buffer/4`).
   If the queue doesn't have enough, it delivers what it has and requests more
   from upstream.

4. **As the queue empties**, it automatically issues new demands upstream to
   stay close to its target size.

## Demand is overwritten, not accumulated

A critical property of `handle_demand/5`: the `demand_size` argument is the
**total current demand** from downstream, not a delta. If the downstream
element requested 5 buffers and then requested 16 more before the first
request was fulfilled, `handle_demand` will be called once with `16` — not
twice with `5` and `16`, and not once with `21`.

This means the element does not need to track previously received demands.
It simply produces as many buffers as `handle_demand` says.

## Demand units

The `demand_unit` option in the pad spec controls how "how much data" is
measured. It affects both the value passed to `handle_demand/5` on the
upstream side and the size argument of the `:demand` action.

### `:buffers` and `:bytes`

These are the classic demand units.

With `:buffers`, the demand is a count of buffers. With `:bytes`, the demand
is a number of payload bytes. When demanding by bytes, the input queue will
split buffers at exact byte boundaries if needed — the resulting fragments
share the same metadata and timestamps as the original buffer.

```elixir
def_input_pad :input,
  flow_control: :manual,
  demand_unit: :buffers,
  accepted_format: _any

@impl true
def handle_demand(:output, demand_size, :buffers, _ctx, state) do
  buffers = produce_buffers(demand_size, state)
  {[buffer: {:output, buffers}], state}
end
```

#### Deadlocks

The most common pitfall with `:buffers`/`:bytes` demands is a deadlock: the
downstream element is waiting for buffers that will never arrive because the
upstream element stopped producing.

This happens when a filter produces fewer buffers than demanded. For example,
if downstream demanded 10 and the filter only sent 8, the downstream will wait
forever for the remaining 2 — unless something triggers another `handle_demand`
call.

There are two ways to avoid this:

1. **Track the shortfall explicitly** — if the filter knows it sent fewer
   buffers than demanded, it can issue an explicit `:demand` action on its
   input to trigger another round of processing.

2. **Use the `:redemand` action** — returning
   [`:redemand`](`t:Membrane.Element.Action.redemand/0`) causes Membrane to
   re-invoke `handle_demand` with the remaining unfulfilled demand. This is a
   safe way to signal "I may not be done yet, check again." If there is no
   outstanding demand on the output, `:redemand` has no effect.

> #### Deadlocks are intermittent {: .warning}
>
> Deadlocks caused by under-producing are especially tricky because they only
> manifest sometimes: if downstream happens to issue a new demand while the
> filter is still processing, the deadlock is avoided. This makes them easy to
> miss in testing.

#### Sending slightly more than demanded

It is acceptable to send slightly more buffers than demanded. The extra buffers
will be buffered in the downstream queue. This can be useful to avoid waiting
for one more demand round-trip when a buffer is already ready.

However, the overshoot should always be a small, **bounded constant** — never
proportional to the stream or unbounded. If the filter always sends `n+k`
buffers when asked for `n`, the downstream queue will grow by `k` on every
cycle and eventually overflow.

### Timestamp demand units

Timestamp demand units let an element request data in terms of _time duration_
rather than buffer count or byte size. This is useful when the element needs to
process a fixed time window of media regardless of how many buffers that window
contains — for example, always consuming exactly 40 ms of audio.

Timestamp demand units are only applicable to **input pads**. Output pads do
not support them. If an input pad uses a timestamp demand unit and the upstream
element's linked output pad does not specify a `demand_unit`, that element will
receive `handle_demand/5` with the demand expressed in `:buffers`.

The available variants are:

- `:timestamp` or `{:timestamp, :dts_or_pts}` — uses DTS if present on a
  buffer, falls back to PTS.
- `{:timestamp, :pts}` — uses the PTS field of each buffer.
- `{:timestamp, :dts}` — uses the DTS field of each buffer.

When using a timestamp unit, the demand size is a `t:Membrane.Time.t/0`
value (nanoseconds). The queue delivers buffers until the elapsed timestamp
span — measured as `last_consumed_buffer.ts - first_consumed_buffer.ts` —
reaches the demanded duration.

**Key difference from `:buffers`/`:bytes`**: timestamp demand does _not_
decrement as buffers are consumed. The demanded duration is a fixed threshold,
not a shrinking counter. Once the demanded window has been satisfied, the
element must issue a new, _larger_ demand to make progress. Issuing the same
demand again after the window has elapsed will produce a warning and deliver no
buffers.

A typical pattern for time-based pacing:

```elixir
def_input_pad :input,
  flow_control: :manual,
  demand_unit: {:timestamp, :dts},
  accepted_format: _any

@impl true
def handle_init(_ctx, opts) do
  {[], %{window_end: Membrane.Time.milliseconds(40)}}
end

@impl true
def handle_demand(:output, _demand_size, :buffers, _ctx, state) do
  # Advance the window by 40 ms each time the downstream asks for more data
  {[demand: {:input, state.window_end}],
   %{state | window_end: state.window_end + Membrane.Time.milliseconds(40)}}
end
```

In this example, successive demands are `40ms`, `80ms`, `120ms`, … All are
measured from the timestamp of the very first buffer ever consumed on the pad,
so each demand naturally covers the next 40 ms slice of the stream.

> #### Buffers must carry timestamps {: .warning}
>
> When using a timestamp demand unit, every buffer in the stream must have
> its relevant timestamp field (`:pts` or `:dts`) set to a non-`nil` value.
> Missing timestamps will cause the queue to behave incorrectly.

> #### Timestamps should be monotonic {: .warning}
>
> The queue assumes that timestamps are non-decreasing. Non-monotonic
> timestamps (e.g. those produced by B-frame reordering when using `:pts`)
> will trigger a warning. Prefer `{:timestamp, :dts}` for streams where DTS
> is available and monotonic.
