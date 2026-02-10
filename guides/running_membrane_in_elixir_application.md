# Using Membrane in Elixir Application

This guide provides tips for using Membrane Pipelines in your Elixir application.
We will cover topics like attaching pipelines to application's supervision tree.

## Configuring Telemetry

## Running the pipeline

In most cases, pipelines are used in the following scenarios:

- Batch Processing: Handling "offline" tasks that have a clear start and end. For example, transcoding stream inside an MP4 container file.
- Static Orchestration: when you need to have a single pipeline always running in your application. For instance you might want to take an input from a bunch of IP cameras and mix their output into a single stream which you distribute over HLS.
- Dynamic Orchestration: Spawning pipelines on demand based on user actions. It happens when e.g. you need to start a unique pipeline for every user who joins a videoconferencing room.

### Batch Processing

Batch processing is applicable in a scenario where you are performing some "offline task". It's good to be sure that the task has finished sucessfully.
Let's assume that we want to transcode and transmux H.264 in MP4 container into VP8 in Matrioska container.
To do so, we need to build the pipeline like this:

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

Next let's create an Oban worker. Using it will ensure that the transcoding is restarted if it fails.

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

### Static Orchestration with the pipeline spawned under Supervisor upon system startup

You can create a dedicated supervisor to manage the pipeline and any "side-car" processes (like a metrics reporter) as a single unit.

```elixir
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

Usage of `:one_for_all` strategy ensures that the `MetricsReporter` get restarted each time the pipeline restarts.

To launch this when your app boots, add the InfrastructureSupervisor to the children list in your `application.ex`:

```elixir
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
