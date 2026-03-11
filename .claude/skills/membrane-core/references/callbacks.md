# Membrane Framework — Callback Reference

## Every Component ([Pipeline](https://hexdocs.pm/membrane_core/Membrane.Pipeline.md), [Bin](https://hexdocs.pm/membrane_core/Membrane.Bin.md), [Element](https://hexdocs.pm/membrane_core/Membrane.Element.Base.md))

| Callback | When called | Default |
|----------|-------------|---------|
| `handle_init/2` | Spawned (sync, blocks parent) | converts opts struct to map |
| `handle_setup/2` | After init (async) | no-op |
| `handle_playing/2` | Entering `:playing` | no-op |
| `handle_terminate_request/2` | Termination requested | `{[terminate: :normal], state}` |
| `handle_info/3` | Any non-Membrane Erlang message | logs warning |
| `handle_tick/3` | Timer tick (started with `:start_timer` action) | no-op |

---

## Parent Components Only ([Pipeline](https://hexdocs.pm/membrane_core/Membrane.Pipeline.md) and [Bin](https://hexdocs.pm/membrane_core/Membrane.Bin.md))

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

---

## Child Components Only ([Bin](https://hexdocs.pm/membrane_core/Membrane.Bin.md) and all Elements)

| Callback | When called | Default |
|----------|-------------|---------|
| `handle_parent_notification/3` | Parent sent a notification | no-op |
| `handle_pad_added/3` | Dynamic pad linked | no-op |
| `handle_pad_removed/3` | Dynamic pad unlinked | no-op |

**Lifecycle note for `handle_pad_added/3`:**
- Fires *before* `handle_playing/2` when the dynamic pad is linked in **the same spec** that spawns the component
- Fires *after* `handle_playing/2` when the pad is linked in a **later spec**

---

## Pipeline Only ([Membrane.Pipeline](https://hexdocs.pm/membrane_core/Membrane.Pipeline.md))

| Callback | When called | Default |
|----------|-------------|---------|
| `handle_call/3` | Synchronous call from an external process via `Membrane.Pipeline.call/3` | no-op |

---

## Elements with Input Pads ([Filter](https://hexdocs.pm/membrane_core/Membrane.Filter.md), [Sink](https://hexdocs.pm/membrane_core/Membrane.Sink.md), [Endpoint](https://hexdocs.pm/membrane_core/Membrane.Endpoint.md)) — [Membrane.Element.WithInputPads](https://hexdocs.pm/membrane_core/Membrane.Element.WithInputPads.md)

| Callback | When called | Default |
|----------|-------------|---------|
| `handle_stream_format/4` | Stream format received on input pad | Filter: forwards downstream |
| `handle_start_of_stream/3` | First buffer about to arrive on input pad | no-op |
| `handle_buffer/4` | Buffer received on input pad | — (no default, must implement) |
| `handle_end_of_stream/3` | EOS received on element's own input pad | Filter: forwards downstream |

---

## Elements with Output Pads ([Source](https://hexdocs.pm/membrane_core/Membrane.Source.md), [Filter](https://hexdocs.pm/membrane_core/Membrane.Filter.md), [Endpoint](https://hexdocs.pm/membrane_core/Membrane.Endpoint.md)) — [Membrane.Element.WithOutputPads](https://hexdocs.pm/membrane_core/Membrane.Element.WithOutputPads.md)

| Callback | When called | Default |
|----------|-------------|---------|
| `handle_demand/5` | Downstream requested data on a `:manual` output pad | — (no default, must implement if using `:manual` flow) |

---

## Events (All Elements) — [Membrane.Event](https://hexdocs.pm/membrane_core/Membrane.Event.md)

| Callback | When called | Default |
|----------|-------------|---------|
| `handle_event/4` | Event received on any pad | Filter: forwards; others: no-op |

**Key property of events**: unlike buffers and stream formats, events can travel both **upstream and downstream**.
