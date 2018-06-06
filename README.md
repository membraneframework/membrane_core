# Membrane Multimedia Framework: Core

This package provides core of the Membrane multimedia framework.


# Installation

Add the following line to your `deps` in `mix.exs`.  Run `mix deps.get`.

```elixir
{:membrane_core, git: "git@github.com:membraneframework/membrane-core.git"}
```

Then add the following line to your `applications` in `mix.exs`.

```elixir
:membrane_core
```

# Getting started

To get familiar with basic concepts and build your first application using Membrane Framework, visit [Membrane Guide](TODO).

API documentation is available on [HexDocs](https://hexdocs.pm/membraneframework)

To set up a pipeline you need to create a module, use Membrane.Pipeline, and implement handle_init/1 callback

# Support and questions

If you have any problems with Membrane Framework feel free to contact us on the [mailing list](https://groups.google.com/forum/#!forum/membrane-framework)

```elixir
defmodule MyPipeline do
  use Membrane.Pipeline
  
  alias Membrane.Element.{File, Mad, PulseAudio}
  
  def handle_init(_args) do
    children = %{
      file_source: {File.Source, File.Source.Options{location: "my_file.mp3"}},
      decoder: Mad.Decoder,
      pulse_sink: {PulseAudio.Sink, PulseAudio.Sink.Options{ringbuffer_size_elements: 8192}},
    }
    links = %{
      {:file_source, :source} => {:mad, :sink},
      {:mad, :source} => {:pulse_sink, :sink}
    }
    spec = %Pipeline.Spec{children: children, links: links}
    state = %{}
    {{:ok, spec}, state}
  end
end
```

# Building documentation

Fetch the dependencies first:

```sh
mix deps.get
```

then you can generate documentation:

```sh
mix docs
```

HTML documentation will be built into `doc/` directory.


# Authors

* Marcin Lewandowski
* Mateusz Front

