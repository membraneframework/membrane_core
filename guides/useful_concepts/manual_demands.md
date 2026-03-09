# Manual demands

Elements with pads using manual flow control have two responsibilities:

- **Output pads**: produce the amount of data requested in the
  [`handle_demand/5`](`c:Membrane.Element.WithOutputPads.handle_demand/5`)
  callback, or less if the stream ends (by returning an
  [`:end_of_stream`](`t:Membrane.Element.Action.end_of_stream/0`) action).
- **Input pads**: explicitly request data using the
  [`:demand`](`t:Membrane.Element.Action.demand/0`) action — data only arrives
  after demand has been issued.

## Output pads and `handle_demand`

When downstream requests data, Membrane invokes
[`handle_demand/5`](`c:Membrane.Element.WithOutputPads.handle_demand/5`) on the
element whose output pad with manual flow control is connected to that
downstream. The callback receives the pad name, the demanded amount, and the
demand unit. The element is expected to produce and send that amount of data,
or less if the stream ends.

The unit in which `demand_size` is expressed is resolved as follows:

1. If the **output pad** declares `demand_unit: :buffers | :bytes`, that unit
   is used.
2. Otherwise, if the linked **input pad** uses `:buffers` or `:bytes`, that
   unit is inherited.
3. Otherwise — when the input pad uses a timestamp demand unit or has auto
   flow control — the output pad inherits `:buffers`.

So the output pad can explicitly control the unit it receives demand in, but
timestamp units are not available on output pads.

### Declarative nature of `handle_demand`

[`handle_demand/5`](`c:Membrane.Element.WithOutputPads.handle_demand/5`) always
receives the **total current outstanding demand** from downstream, not a delta.
There is no need to accumulate demand values across multiple callback invocations — each
call tells you the full amount still expected.

### Producing buffers on demand

A source generating random buffers:

```elixir
defmodule MySource do
  use Membrane.Source

  def_output_pad :output,
    flow_control: :manual,
    demand_unit: :buffers,
    accepted_format: _any

  @impl true
  def handle_demand(:output, demand_size, :buffers, _ctx, state) do
    buffers = Enum.map(1..demand_size, fn _ ->
      %Membrane.Buffer{payload: :crypto.strong_rand_bytes(256)}
    end)
    {[buffer: {:output, buffers}], state}
  end
end
```

A source generating random bytes:

```elixir
defmodule MyBytesSource do
  use Membrane.Source

  def_output_pad :output,
    flow_control: :manual,
    demand_unit: :bytes,
    accepted_format: _any

  @impl true
  def handle_demand(:output, demand_size, :bytes, _ctx, state) do
    buffer = %Membrane.Buffer{payload: :crypto.strong_rand_bytes(demand_size)}
    {[buffer: {:output, buffer}], state}
  end
end
```

### Redemand

Sometimes producing all demanded buffers at once is not possible or not
desired — for example when the element generates one buffer at a time. In that
case, return the [`:redemand`](`t:Membrane.Element.Action.redemand/0`) action
alongside the buffer. Membrane will then invoke
[`handle_demand/5`](`c:Membrane.Element.WithOutputPads.handle_demand/5`) again
with the demand reduced by the size of what was just sent.

```elixir
@impl true
def handle_demand(:output, _demand_size, :buffers, _ctx, state) do
  buffer = %Membrane.Buffer{payload: :crypto.strong_rand_bytes(256)}
  {[buffer: {:output, buffer}, redemand: :output], state}
end
```

If demand starts at 5, the call sequence looks like this:

```
handle_demand(:output, 5, :buffers, ctx, state)  # → sends 1 buffer, redemands
handle_demand(:output, 4, :buffers, ctx, state)  # → sends 1 buffer, redemands
handle_demand(:output, 3, :buffers, ctx, state)  # → sends 1 buffer, redemands
handle_demand(:output, 2, :buffers, ctx, state)  # → sends 1 buffer, redemands
handle_demand(:output, 1, :buffers, ctx, state)  # → sends 1 buffer, redemands
# demand reaches 0 — handle_demand is not called again until new demand arrives
```

## Input pads and the demand action

To receive data on an input pad with manual flow control, the element must
issue a [`:demand`](`t:Membrane.Element.Action.demand/0`) action. The demand
unit is declared in the input pad spec.

### `:buffers` and `:bytes`

#### Example: a sink demanding buffers

Below is a sink that every second demands 5 buffers and appends their payloads
to a file. This sink is contrived and exists only to demonstrate the demand
mechanism.

```elixir
defmodule MyDemoSink do
  use Membrane.Sink

  def_input_pad :input,
    flow_control: :manual,
    demand_unit: :buffers,
    accepted_format: _any

  @impl true
  def handle_playing(_ctx, state) do
    {[start_timer: {:demand_timer, Membrane.Time.seconds(1)},
      demand: {:input, 5}], state}
  end

  @impl true
  def handle_tick(:demand_timer, _ctx, state) do
    {[demand: {:input, 5}], state}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    File.write!("output.bin", buffer.payload, [:append])
    {[], state}
  end
end
```

#### Example: demanding bytes

The same sink, but demanding 100 bytes at a time instead of 5 buffers:

```elixir
defmodule MyBytesDemoSink do
  use Membrane.Sink

  def_input_pad :input,
    flow_control: :manual,
    demand_unit: :bytes,
    accepted_format: _any

  @impl true
  def handle_playing(_ctx, state) do
    {[start_timer: {:demand_timer, Membrane.Time.seconds(1)},
      demand: {:input, 100}], state}
  end

  @impl true
  def handle_tick(:demand_timer, _ctx, state) do
    {[demand: {:input, 100}], state}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    File.write!("output.bin", buffer.payload, [:append])
    {[], state}
  end
end
```

When demanding in bytes, if a buffer boundary does not align with the requested
byte count, the buffer is split. Both fragments share the same metadata and
timestamps as the original buffer.

#### Declarative nature of demands

This section applies to `:buffers` and `:bytes` demand units. Timestamp demand
units behave differently — see the [timestamp section](#timestamp-demand-units)
below.

The `:demand` action **overwrites** the current demand — it does not add to it.
Issuing `demand: {:input, 5}` sets the demand to 5 regardless of how much
demand was already pending.

This matters when a new demand is issued before the previous one is fully
satisfied. For example, if you demand 5, receive 3 buffers, then demand 5
again:

| Event | Demand |
|-------|--------|
| `demand: {:input, 5}` | 5 |
| buffer received | 4 |
| buffer received | 3 |
| buffer received | 2 |
| `demand: {:input, 5}` | 5 ← overwrites 2 |
| buffer received | 4 |
| buffer received | 3 |
| buffer received | 2 |
| buffer received | 1 |
| buffer received | 0 |

Total received: **8**, not 10. The remaining 2 from the first demand were
discarded when the second `demand: {:input, 5}` was issued.

If you need to accumulate demand rather than overwrite it, use the function
form:

```elixir
{[demand: {:input, &(&1 + 5)}], state}
```

### Timestamp demand units

Timestamp demand units let an element request buffers by specifying a
**timestamp threshold** rather than a count or byte size. The element receives
all buffers up to and including the first one whose timestamp meets or exceeds
the demanded value.

Timestamp demand units are only applicable to **input pads with manual flow
control**. Output pads do not support them. If an input pad uses a timestamp
demand unit and the linked upstream output pad does not specify a `demand_unit`,
that element will receive [`handle_demand/5`](`c:Membrane.Element.WithOutputPads.handle_demand/5`) with demand expressed in `:buffers`.

#### Available variants

- `{:timestamp, :pts}` — uses each buffer's `:pts` field.
- `{:timestamp, :dts}` — uses each buffer's `:dts` field.
- `:timestamp` or `{:timestamp, :dts_or_pts}` — uses `buffer.dts || buffer.pts`.

#### Timestamp requirements

All buffers passing through an input pad with a timestamp demand unit must have
their relevant timestamp field set to a non-`nil` value — Membrane will raise
an error if a buffer is missing its timestamp. Additionally, timestamps must be
**monotonically non-decreasing**; non-monotonic timestamps will cause a warning.

For `{:timestamp, :pts}`, note that PTS can be non-monotonic in streams with
B-frames (see the [timestamps guide](timestamps.md)). Prefer
`{:timestamp, :dts}` or `{:timestamp, :dts_or_pts}` when DTS is available.

#### How timestamp demands work

The demand value is a `t:Membrane.Time.t/0` value. Use `Membrane.Time`
functions to construct it, for example `Membrane.Time.seconds(1)`.

Timestamps are interpreted relative to an **offset** — the timestamp of the
very first buffer ever received on the pad. This means you never need to know
the absolute starting timestamp of the stream; you only work with durations
from that origin.

For example, if the first buffer arrives with `pts: Membrane.Time.seconds(100)`
and you issue `demand: {:input, Membrane.Time.seconds(1)}`, Membrane will
deliver buffers until it reaches the first one with
`pts >= Membrane.Time.seconds(100) + Membrane.Time.seconds(1)`, i.e.
`pts >= Membrane.Time.seconds(101)`.

When you issue `demand: {:input, t}`, Membrane delivers all buffered buffers
whose timestamp (minus the offset) is strictly less than `t`, plus the first
buffer whose timestamp (minus the offset) equals or exceeds `t`. This means
that **if you demand a value strictly greater than the last received buffer's
timestamp (minus the offset), you are guaranteed to receive at least one new
buffer**.

#### Incrementing demands

To receive a continuous stream in time-based chunks, always demand a value
larger than the timestamp (minus the offset) of the last received buffer.
Issuing a demand at or below that value will result in a warning and no buffers
being delivered.

#### Example: a sink consuming one second of data per second

```elixir
defmodule MyTimestampSink do
  use Membrane.Sink

  # For demonstration purposes only.

  def_input_pad :input,
    flow_control: :manual,
    demand_unit: {:timestamp, :pts},
    accepted_format: _any

  @impl true
  def handle_playing(_ctx, state) do
    {[start_timer: {:demand_timer, Membrane.Time.seconds(1)},
      demand: {:input, Membrane.Time.seconds(1)}],
     %{state | next_demand: Membrane.Time.seconds(2)}}
  end

  @impl true
  def handle_tick(:demand_timer, _ctx, state) do
    {[demand: {:input, state.next_demand}],
     %{state | next_demand: state.next_demand + Membrane.Time.seconds(1)}}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    File.write!("output.bin", buffer.payload, [:append])
    {[], state}
  end
end
```

Each timer tick advances the demanded threshold by one second: `1s`, `2s`,
`3s`, … All values are measured from the PTS of the very first buffer received
on `:input`, so each demand naturally covers the next one-second slice of the
stream.

## Filters with manual flow control

The canonical pattern for a filter with both pads using manual flow control is:

- **[`handle_demand/5`](`c:Membrane.Element.WithOutputPads.handle_demand/5`)** — propagate the demand upstream by returning a [`:demand`](`t:Membrane.Element.Action.demand/0`) action on the input pad.
- **[`handle_buffer/4`](`c:Membrane.Element.WithInputPads.handle_buffer/4`)** — process the incoming buffer and forward it (possibly modified) downstream via a [`:buffer`](`t:Membrane.Element.Action.buffer/0`) action.

The following example combines every two input buffers into one output buffer,
so to satisfy a demand of `n` output buffers, the filter needs `n * 2` input
buffers. 

```elixir
defmodule MyFilter do
  use Membrane.Filter

  def_input_pad :input,
    flow_control: :manual,
    demand_unit: :buffers,
    accepted_format: _any

  def_output_pad :output,
    flow_control: :manual,
    demand_unit: :buffers,
    accepted_format: _any

  @impl true
  def handle_init(_ctx, _opts) do
    {[], %{pending: nil}}
  end

  @impl true
  def handle_demand(:output, demand_size, :buffers, _ctx, state) do
    {[demand: {:input, demand_size * 2}], state}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, %{pending: nil} = state) do
    {[], %{state | pending: buffer}}
  end

  def handle_buffer(:input, buffer, _ctx, %{pending: first} = state) do
    output = %Membrane.Buffer{
      payload: first.payload <> buffer.payload,
      pts: first.pts,
      dts: first.dts,
      metadata: first.metadata
    }
    {[buffer: {:output, output}], %{state | pending: nil}}
  end
end
```

> #### Do not use redemand in a filter's `handle_demand` {: .warning}
>
> Returning [`:redemand`](`t:Membrane.Element.Action.redemand/0`) from
> [`handle_demand/5`](`c:Membrane.Element.WithOutputPads.handle_demand/5`) in a
> filter is illegal. [`handle_demand/5`](`c:Membrane.Element.WithOutputPads.handle_demand/5`)
> should propagate the demand upstream and return. Processing happens in
> [`handle_buffer/4`](`c:Membrane.Element.WithInputPads.handle_buffer/4`) when
> the data actually arrives.

## Auto flow control

If you are writing a filter that processes buffers one by one without needing
to control the timing or quantity of incoming data, consider auto flow control
instead. With auto flow control, Membrane manages demands automatically: when
all auto output pads have positive demand, it issues demand on all auto input
pads. The element only needs to implement [`handle_buffer/4`](`c:Membrane.Element.WithInputPads.handle_buffer/4`).

```elixir
defmodule MyAutoFilter do
  use Membrane.Filter

  def_input_pad :input,
    flow_control: :auto,
    accepted_format: _any

  def_output_pad :output,
    flow_control: :auto,
    accepted_format: _any

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    processed = %{buffer | payload: process(buffer.payload)}
    {[buffer: {:output, processed}], state}
  end

  defp process(payload) do
    for <<byte <- payload>>, into: <<>>, do: <<Bitwise.bxor(byte, 0xFF)>>
  end
end
```

Use manual flow control when the element needs to control the timing or
quantity of incoming data explicitly — for example when producing a fixed time
window of buffers, or when the ratio between input and output buffers is not
fixed.
