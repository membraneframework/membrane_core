# Using Membrane in Elixir Application
This guide outlines best practices for integrating Membrane Pipelines into your Elixir application, specifically focusing on how to attach pipelines to your application's supervision tree.

## Running the pipeline

In most cases, pipelines are used in one of the following scenarios:

- Batch Processing: Handling "offline" tasks with a clear start and end (e.g., transcoding a stream inside an MP4 file).

- Static Orchestration: Maintaining a single, permanent pipeline that always runs with your application (e.g., mixing output from multiple IP cameras into a single HLS stream).

- Dynamic Orchestration: Spawning pipelines on-demand based on user actions (e.g., starting a unique pipeline for every user joining a conference room).

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

To ensure reliability, we might wrap this execution in an Oban worker.
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
  "input_path" => "uploads/raw_video.mp4",
  "output_path" => "processed/optimized_video.mkv"
}
|> VideoTranscoderWorker.new()
|> Oban.insert()
```
### Static Orchestration: Supervisor on Startup
This approach is ideal when your pipeline architecture is fixed and needs to run continuously from the moment your application starts.
Imagine an application that monitors a security camera feed to detect people or vehicles in real-time. Such an application could consist of two components:
* The Membrane Pipeline, which connects to an RTSP stream, decodes the video, and extracts raw frames. It sends these frames to the external process via a Unix socket or standard input.
* The OS Process being a Python script running a machine learning model (like YOLO). It reads the raw frames, performs object detection, and outputs metadata (bounding boxes, class labels).

To handle this scenario, you could create a dedicated supervisor to manage the pipeline alongside any necessary "side-car" processes—such as a `MuonTrap.Daemon` wrapping an external OS command.
This allows you to treat the pipeline and its dependencies as a single  unit.

```elixir
defmodule MyProject.InfrastructureSupervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(rtmp_url) do
    children = [
      {MuonTrap.Daemon, ["run_model", ["yolo.pth"], [log_output: :debug]], restart: :transient]}
      {MyProject.Pipeline, [input_url: rtmp_url], restart: :transient}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
```

Usage of `:one_for_all` strategy ensures that the `MuonTrap.Deamon` get restarted each time the pipeline restarts.

To launch this when your app boots, add the `InfrastructureSupervisor` to the children list in your `application.ex`:

```elixir
defmodule MyProject.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {MyProject.InfrastructureSupervisor, [rtmp_url: "rtmp://127.0.0.1:1935/app/key"]}
    ]

    opts = [strategy: :one_for_one, name: MyProject.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

### Dynamically spawning the pipelines under the DynamicSupervisor

Since we already have the InfrastructureSupervisor, implementation is straightforward.
Instead of starting the `InfrastructureSupervisor` directly in the application, you start a `DynamicSupervisor` there.

```elixir
defmodule MyProject.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {DynamicSupervisor, strategy: :one_for_one, name: MyProject.DynamicSupervisor}
    ]

    opts = [strategy: :one_for_one, name: MyProject.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

Then, whenever a new pipeline is needed, you use `DynamicSupervisor.start_child()` to spawn a new instance of the `InfrastructureSupervisor`.
It could happen e.g. inside `mount/3` callback of your LiveView:

```elixir
def mount(_params, _session, socket) do
  ...
  if connected?(socket) do
    ...
    {:ok, _pid} = DynamicSupervisor.start_child(
      MyProject.PipelineDynamicSupervisor,
      {MyProject.InfrastructureSupervisor, [input_url: "rtmp://127.0.0.1:1935/app/key"]}
    )
  end
end
```
