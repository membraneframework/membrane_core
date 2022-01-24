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
      |> via_in(:input, demand_excess: 10)
      |> to(:filter)
      |> via_in(:input, demand_excess: 10)
      |> to(:consumer)
    ]

    spec = %Membrane.ParentSpec{
      children: children,
      links: links
    }

    {{:ok, spec: spec}, %{}}
  end
end
