# Membrane Framework — Integration & Examples Reference

## Integration Patterns

### Static — Always-on Pipeline (Application Supervisor)

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

### Dynamic — Per-User / Per-Request Pipelines

```elixir
# application.ex — add a DynamicSupervisor
{DynamicSupervisor, strategy: :one_for_one, name: MyApp.PipelineSupervisor}

# Spawn on demand (e.g. in a LiveView mount or HTTP handler)
{:ok, _sup} = DynamicSupervisor.start_child(
  MyApp.PipelineSupervisor,
  {Membrane.Pipeline, [MyPipeline, opts]}
)

# Tear down
DynamicSupervisor.terminate_child(MyApp.PipelineSupervisor, sup_pid)
```

### Batch — Wait for Pipeline to Finish

```elixir
{:ok, _sup, pipeline_pid} = Membrane.Pipeline.start_link(TranscodePipeline, opts)
ref = Process.monitor(pipeline_pid)
receive do
  {:DOWN, ^ref, :process, ^pipeline_pid, :normal} -> :ok
end
```

---

## Demo Examples

The [`membraneframework/membrane_demo`](https://github.com/membraneframework/membrane_demo) monorepo has runnable examples:

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

## Key Source File Locations

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
