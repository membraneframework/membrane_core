defmodule Membrane.Support.Element.TrivialPipeline do
  use Membrane.Pipeline

  alias Membrane.Support.Element.{TrivialFilter, TrivialSink, TrivialSource}

  @impl true
  def handle_init(_ctx, _) do
    children = [
      producer: TrivialSource,
      filter: TrivialFilter,
      consumer: TrivialSink
    ]

    links = [
      get_child(:producer)
      |> via_in(:input, target_queue_size: 10)
      |> get_child(:filter)
      |> via_in(:input, target_queue_size: 10)
      |> get_child(:consumer)
    ]

    spec = %Membrane.ChildrenSpec{
      structure: children ++ links
    }

    {{:ok, spec: spec}, %{}}
  end
end
