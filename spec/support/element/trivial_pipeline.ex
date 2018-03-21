defmodule Membrane.Support.Element.TrivialPipeline do
  alias Membrane.Pipeline
  alias Membrane.Support.Element.{TrivialSource, TrivialFilter, TrivialSink}
  use Membrane.Pipeline

  def handle_init(_) do
    children = %{
      producer: TrivialSource,
      filter: TrivialFilter,
      consumer: TrivialSink
    }

    links = %{
      {:producer, :source} => {:filter, :sink, pull_buffer: %{preferred_size: 10}},
      {:filter, :source} =>
        {:consumer, :sink, pull_buffer: %{preferred_size: 10, initial_size: 5}}
    }

    spec = %Pipeline.Spec{
      children: children,
      links: links
    }

    {{:ok, spec}, nil}
  end
end
