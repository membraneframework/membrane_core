# Using Membrane in Elixir Applications
This guide provides tips for using Membrane Pipelines in your Elixir application.


## Telemetry

## Spawning under supervisor
In most cases, pipelines are used for:

* Batch Processing: Handling "offline" tasks that have a clear start and end. For example, converting an MP4 file (with H.264 stream) into a Matroska container (with VP8 stream).
* Static Orchestration: 
* Dynamic Orchestration: Spawning pipelines on demand based on user actions. For example, starting a unique pipeline for every user who joins a videoconferencing room.


### Static Orchestration with the pipeline spawned under Supervisor upon system startup

This scenario is applicable when the architecture of the system is fixed and known at the startup of you application.
You can create a dedicated supervisor to manage the pipeline and any "side-car" processes (like a metrics reporter) as a single unit.
```
defmodule MyProject.InfrastructureSupervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      {MyProject.MetricsReporter, name: MetricsReporter},
      {MyProject.Pipeline, [input_url: "rtmp://127.0.0.1:1935/app/key"]}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end  
```
Use `:one_for_all` strategy to make sure the `MetricsReporter` get restarted each time the pipeline restarts.

To launch this when your app boots, add the InfrastructureSupervisor to the children list in your application.ex:

```
defmodule MyProject.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MyProject.InfrastructureSupervisor
    ]

    opts = [strategy: :one_for_one, name: MyProject.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

### Dynamic Spawning the pipelines spawned dynamically under DynamicSupervisor

Since we already have the InfrastructureSupervisor, implementation is straightforward.
Instead of starting the `InfrastructureSupervisor` directly in the application, you start a `DynamicSupervisor` there.

```
  
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
Then, whenever a new pipeline is needed, you use `DynamicSupervisor.start_child()`` to spawn a new instance of the `InfrastructureSupervisor`.
```
{:ok, pid} = DynamicSupervisor.start_child(
  MyProject.PipelineDynamicSupervisor,
  {MyProject.InfrastructureSupervisor, [input_url: "rtmp://127.0.0.1:1935/app/key"]}
)
```

### Batch Processing

Batch processing is applicable in a scenario where you are performing some "offline task". It's good to be sure that the task has finished sucessfully.
Let's assume that we want to transcode and transmux H.264 in MP4 container into VP8 in Matrioska container.
To do so, we need to build the pipeline like this:
```
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

Next let's create an Oban worker. Using it will ensure that the transcoding is restarted if it fails.
```
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
```
%{
  "input_path" => "uploads/raw_video.mp4",
  "output_path" => "processed/optimized_video.mkv"
}
|> VideoTranscoderWorker.new()
|> Oban.insert()
```
