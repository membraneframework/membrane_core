# Using Membrane in Elixir Application

This guide outlines best practices for integrating Membrane Pipelines into your Elixir application, specifically focusing on how to attach pipelines to your application's supervision tree.

## Running the pipelines reliably

In most cases, pipelines are used in one of the following scenarios:

- Batch Processing: Handling "offline" tasks with a clear start and end (e.g. transcoding a stream inside an MP4 file).

- Static Orchestration: Maintaining a single, permanent pipeline that always runs with your application (e.g. mixing output from multiple IP cameras into a single HLS stream).

- Dynamic Orchestration: Spawning pipelines on-demand based on user actions (e.g. starting a unique pipeline for every user joining a conference room).

### Batch Processing

Batch processing is ideal for "offline tasks" where you need to ensure the job completes successfully.

For example, let's assume we want to transcode video from H.264 (in MP4) to VP8 (in Matroska). To achieve this, we build the pipeline as follows:

```elixir
defmodule TranscodePipeline do
  use Membrane.Pipeline

  alias Membrane.File.{Source, Sink}
  alias Membrane.H264.FFmpeg.Parser
  alias Membrane.FFmpeg.SWScale.PixelFormatConverter

  @impl true
  def handle_init(_ctx, opts) do
    structure = [
      child(:source, %Source{location: opts[:input_path]})
      |> child(:demuxer, Membrane.MP4.Demuxer.ISOM)
      |> via_out(:video)
      |> child(:parser, %Parser{generate_best_effort_timestamps: true})
      |> child(:decoder, Membrane.H264.FFmpeg.Decoder)
      |> child(:converter, %PixelFormatConverter{format: :I420})
      |> child(:encoder, Membrane.VP8.Encoder)
      |> child(:muxer, Membrane.Matroska.Muxer)
      |> child(:sink, %Sink{location: opts[:output_path]})
    ]

    {[spec: structure], %{}}
  end
end
```

To ensure reliability, we might wrap this execution in an [Oban](https://hexdocs.pm/oban/Oban.html) worker.

Oban is the standard library for background job processing in Elixir. It persists jobs to your database, ensuring that your long-running transcoding tasks are fault-tolerant.
If the pipeline crashes or the server restarts, Oban will automatically retry the job until it succeeds.

Let's define an Oban worker:

```elixir
defmodule VideoTranscoderWorker do
  @timeout_sec :time
    
  use Oban.Worker, queue: :media, unique: [period: 60], timeout: :timer.seconds(10)

  @impl true
  def perform(%Oban.Job{args: %{"input_path" => input, "output_path" => output}}) do
    {:ok, _supervisor_pid, pipeline_pid} = Membrane.Pipeline.start_link(
      TranscodePipeline, 
      [input_path: input, output_path: output]
    )

    case Membrane.Pipeline.wait_for_termination(pipeline_pid, 100_000) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
```

Now we can run the Oban worker:

```elixir
%{
  "input_path" => "uploads/input_video.mp4",
  "output_path" => "processed/transcoded_video.mkv"
}
|> VideoTranscoderWorker.new()
|> Oban.insert()
```

When the job terminates successfully, you will see the output `.mkv` file with transcoded video.

### Static Orchestration: Supervisor on Startup

This approach is ideal when your pipeline architecture is fixed and needs to run continuously from the moment your application starts.
Imagine an application that monitors a security camera feed to detect people or vehicles in real-time. Such an application could consist of two components:

- The Membrane Pipeline, which connects to an RTSP stream, decodes the video, and extracts raw frames. It sends these frames to the external process via a Unix socket or standard input.
- The OS Process being a Python script running a machine learning model (like YOLO). It reads the raw frames, performs object detection, and outputs metadata (bounding boxes, class labels).

To handle this scenario, you could create a dedicated supervisor to manage the pipeline alongside any necessary "side-car" processes—such as a [`MuonTrap.Daemon`](https://hexdocs.pm/muontrap/readme.html) wrapping an external OS command.
This allows you to treat the pipeline and its dependencies as a single unit.

```elixir
defmodule MyProject.InfrastructureSupervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(rtsp_url) do
    children = [
      {MuonTrap.Daemon, ["python", ["run_model.py", "yolo.pth"], [log_output: :debug]], restart: :transient]}
      {MyProject.Pipeline, [input_url: rtsp_url], restart: :transient}
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
      {MyProject.InfrastructureSupervisor, [rtsp_url: "rtsp://user:password@127.0.0.1:554"]}
      # ... other children required by your application
    ]

    opts = [strategy: :one_for_one, name: MyProject.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

### Dynamically spawning the pipelines under the DynamicSupervisor

While the static approach works perfectly for fixed infrastructure, many applications require more flexibility.
Consider a scenario where you need to spawn a new pipeline on demand to ingest an RTSP stream from a camera provided by a user.

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

Now, whenever a new pipeline is needed you can spawn a new instance of your infrastructure using `DynamicSupervisor.start_child/2`.
It could happen e.g. inside `mount/3` callback of your LiveView:

```elixir
def mount(params, _session, socket) do
  if connected?(socket) do
    {:ok, _pid} = DynamicSupervisor.start_child(
      MyProject.PipelineDynamicSupervisor,
      {MyProject.InfrastructureSupervisor, params["rtsp_url"]}
    )
  end
  {:ok, socket}
end
```
