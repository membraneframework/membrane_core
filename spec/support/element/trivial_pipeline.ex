defmodule Membrane.Support.Element.TrivialPipeline do
  use Membrane.Pipeline

  alias Membrane.Support.Element.{TrivialFilter, TrivialSink, TrivialSource}

  @impl true
  def handle_init(_) do
    children = [
      producer: TrivialSource,
      filter: TrivialFilter,
      consumer: TrivialSink
    ]

    links = [
      link(:producer)
      |> via_in(:input, target_queue_size: 10)
      |> to(:filter)
      |> via_in(:input, target_queue_size: 10)
      |> to(:consumer)
    ]

    spec = %Membrane.ChildrenSpec{
      structure: children ++ links
    }

    {{:ok, spec: spec}, %{}}
  end
end
