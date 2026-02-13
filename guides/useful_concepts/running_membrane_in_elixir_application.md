# Using Membrane in Elixir Application

This guide outlines best practices for integrating Membrane Pipelines into your Elixir application, specifically focusing on how to attach pipelines to your application's supervision tree.

In most cases, pipelines are used in one of the following scenarios:

- Static Orchestration: Maintaining a single, permanent pipeline that always runs with your application (e.g. mixing output from multiple IP cameras into a single HLS stream).

- Dynamic Orchestration: Spawning pipelines on-demand based on user actions (e.g. starting a unique pipeline for every user joining a conference room).

- Batch Processing: Handling "offline" tasks with a clear start and end (e.g. transcoding a stream inside an MP4 file).

## Static Orchestration: Supervisor on Startup

This approach is ideal when your pipeline architecture is fixed and needs to run continuously from the moment your application starts.
Imagine an application that monitors a security camera feed to detect people or vehicles in real-time. Such an application could consist of two components:

- The Membrane Pipeline which connects to an SRT stream, decodes the video, and extracts raw frames. It sends these frames to the external process (via a Unix socket or standard input), receives the transformed video back, re-encodes it, and broadcasts the final stream using HLS.

- The OS Process being a Python script running a machine learning model like [RF-DETR](https://github.com/roboflow/rf-detr). It reads raw video frames and performs object segmentation, coloring the pixels that correspond to detected objects.

The pipeline could look similar to this one:

```elixir
defmodule MyProject.Pipeline do
  use Membrane.Pipeline

  @impl true
  def handle_init(_ctx, srt_url) do
    hls_config = %Membrane.HTTPAdaptiveStream.SinkBin{
      manifest_module: Membrane.HTTPAdaptiveStream.HLS,
      target_window_duration: Membrane.Time.seconds(120),
      storage: %Membrane.HTTPAdaptiveStream.Storages.FileStorage{
        directory: "output_hls"
      }
    }

    spec = [
      child(:source, %Membrane.SRT.Source{
        transport: :tcp,
        allowed_media_types: [:video],
        stream_uri: srt_url,
        on_connection_closed: :send_eos
      })
      |> child(:depayloader, Membrane.H264.RTP.Depayloader)
      |> child(:parser, Membrane.H264.Parser)
      |> child(:decoder, Membrane.H264.FFmpeg.Decoder)
      |> child(:segmentation_filter, MyProject.ObjectSegmentationFilter) # filter talking with the side-car Python OS process running RF-DETR model
      |> child(:encoder, %Membrane.H264.FFmpeg.Encoder{preset: :fast})
      |> via_in(:input, options: [encoding: :H264, segment_duration: @segment_duration])
      |> child(:hls, hls_config)
    ]

    {[spec: spec], %{}}
  end
end
```

Then you could create a dedicated supervisor to manage the pipeline alongside any necessary "side-car" processes such as a [`MuonTrap.Daemon`](https://hexdocs.pm/muontrap/readme.html) wrapping an external OS command.
This allows you to treat the pipeline and its dependencies as a single unit.

```elixir
defmodule MyProject.InfrastructureSupervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(srt_url) do
    children = [
      {MuonTrap.Daemon, ["python", ["run_model.py", "rf-detr-large-2026.pth"], [log_output: :debug]], restart: :transient]}
      {MyProject.Pipeline, [input_url: srt_url], restart: :transient}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
```

Usage of `:one_for_all` strategy ensures that the `MuonTrap.Deamon` get restarted each time the pipeline restarts and another way around.
In your specific scenario, you may need to adjust the [`:restart`](https://hexdocs.pm/elixir/1.12/Supervisor.html#module-restart-values-restart) and [`:strategy`](https://hexdocs.pm/elixir/1.12/Supervisor.html#module-start_link-2-init-2-and-strategies)
options to reflect the dependencies between supervised processes.

To launch this when your app boots, add the `InfrastructureSupervisor` to the children list in your `application.ex`:

```elixir
defmodule MyProject.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {MyProject.InfrastructureSupervisor, [srt_url: "srt://127.0.0.1:9710"]}
      # ... other children required by your application
    ]

    opts = [strategy: :one_for_one, name: MyProject.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

## Dynamically spawning the pipelines under the DynamicSupervisor

While the static approach works perfectly for fixed infrastructure, many applications require more flexibility.
Consider a scenario where you need to spawn a new pipeline on demand to ingest an SRT stream from a camera provided by a user.

Since we have already defined the `InfrastructureSupervisor`, scaling to multiple dynamic pipelines is straightforward.

Instead of starting the `InfrastructureSupervisor` directly in your application tree, we add a [`DynamicSupervisor`](https://hexdocs.pm/elixir/DynamicSupervisor.html).
This allows us to spawn new infrastructure "units" (the pipeline + sidecars) on demand.

```elixir
defmodule MyProject.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {DynamicSupervisor, strategy: :one_for_one, name: MyProject.PipelineDynamicSupervisor}
      # ... other children required by your application
    ]

    opts = [strategy: :one_for_one, name: MyProject.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

Now, whenever a new pipeline is needed you can spawn a new instance of your infrastructure using [`DynamicSupervisor.start_child/2`](https://hexdocs.pm/elixir/1.12/DynamicSupervisor.html#start_child/2).
It could happen e.g. inside `mount/3` callback of your LiveView:

```elixir
def mount(params, _session, socket) do
  if connected?(socket) do
    {:ok, infrastructure_supervisor_pid} = DynamicSupervisor.start_child(
      MyProject.PipelineDynamicSupervisor,
      {MyProject.InfrastructureSupervisor, params["srt_url"]}
    )
    {:ok, assign(socket, :infrastructure_supervisor_pid, infrastructure_supervisor_pid)}
  else
    {:ok, socket}
  end
end
```

When you need to stop the pipeline, you can use [`DynamicSupervisor.terminate_child/2`](https://hexdocs.pm/elixir/1.12/DynamicSupervisor.html#terminate_child/2).

In case of your LiveView commponent it could happen in its `terminate/2` callback:

```elixir
def terminate(_reason, socket) do
  if pid = socket.assigns[:infrastructure_supervisor_pid] do
    DynamicSupervisor.terminate_child(MyProject.PipelineDynamicSupervisor, pid)
  end
  :ok
end
```

## Batch Processing

Batch processing is ideal for "offline tasks" where you need to ensure the job completes successfully.

For example, let's assume we want to rescale H.264 video in MP4 container. To achieve this, we build the pipeline as follows:

```elixir
defmodule TranscodePipeline do
  use Membrane.Pipeline

  alias Membrane.File.{Source, Sink}
  alias Membrane.H264.FFmpeg.{Decoder, Encoder}
  alias Membrane.H264.Parser
  alias Membrane.FFmpeg.SWScale.Converter

  @impl true
  def handle_init(_ctx, opts) do
    spec = [
      child(:source, %Source{location: opts[:input_path]})
      |> child(:demuxer, Membrane.MP4.Demuxer.ISOM)
      |> via_out(:output, options: [kind: :video])
      |> child(:in_parser, %Parser{output_stream_structure: :annexb})
      |> child(:decoder, Decoder)
      |> child(:converter, %Converter{output_width: 1080, output_height: 720})
      |> child(:encoder, Encoder)
      |> child(:out_parser, %Parser{output_stream_structure: :avc1})
      |> child(:sink, %Sink{location: opts[:output_path]})
    ]

    {[spec: spec], %{}}
  end

  @impl true
  def handle_element_end_of_stream(:sink, :input, _ctx, state), do: {[terminate: :normal], state}

  @impl true
  def handle_element_end_of_stream(_child, _pad, _ctx, state), do: {[], state}
end
```

To ensure reliability, we might wrap execution of the pipeline in an [Oban](https://hexdocs.pm/oban/Oban.html) worker.

Oban is the standard library for background job processing in Elixir. It persists jobs to your database, ensuring that your long-running transcoding tasks are fault-tolerant.
If the pipeline crashes or the server restarts, Oban will automatically retry the job until it succeeds.
To install Oban in your project, you can follow this [installation guide](https://hexdocs.pm/oban/installation.html).

Assuming that Oban is installed in your project and the `:default` queue is configured we can define the Oban worker:

```elixir

defmodule VideoTranscoderWorker do
  use Oban.Worker, queue: :default, unique: [period: 60]

  @impl true
  def perform(%Oban.Job{args: %{"input_path" => input, "output_path" => output}}) do
    {:ok, _supervisor_pid, pipeline_pid} =
      Membrane.Pipeline.start_link(
        TranscodePipeline,
        input_path: input,
        output_path: output
      )

    ref = Process.monitor(pipeline_pid)

    receive do
      {:DOWN, ^ref, :process, ^pipeline_pid, :normal} ->
        :ok
    end
  end

  @impl true
  def timeout(_job), do: :timer.minutes(5)
end
```

Now we can run the Oban worker:

```elixir
%{
  "input_path" => "input.mp4",
  "output_path" => "output.mp4"
}
|> VideoTranscoderWorker.new()
|> Oban.insert()
```

When the job terminates successfully, you will see the output `output.mp4` file with transcoded video.
