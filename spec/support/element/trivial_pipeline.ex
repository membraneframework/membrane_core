defmodule Membrane.Support.Element.TrivialPipeline do
  alias Membrane.Support.Element.{TrivialSource, TrivialFilter, TrivialSink}
  use Membrane.Pipeline

  @impl true
  def handle_init(_) do
    children = [
      producer: TrivialSource,
      filter: TrivialFilter,
      consumer: TrivialSink
    ]

    links = %{
      {:producer, :output} => {:filter, :input, pull_buffer: [preferred_size: 10]},
      {:filter, :output} => {:consumer, :input, pull_buffer: [preferred_size: 10]}
    }

    spec = %Pipeline.Spec{
      children: children,
      links: links
    }

    {{:ok, spec}, %{}}
  end
end
