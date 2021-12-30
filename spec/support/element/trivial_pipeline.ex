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
      |> via_in(:input, demand_excess_factor: 0.25)
      |> to(:filter)
      |> via_in(:input, demand_excess_factor: 0.25)
      |> to(:consumer)
    ]

    spec = %Membrane.ParentSpec{
      children: children,
      links: links
    }

    {{:ok, spec: spec}, %{}}
  end
end
