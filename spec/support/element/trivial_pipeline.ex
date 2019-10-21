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

    links = [
      link(:producer)
      |> via_in(:input, buffer: [preferred_size: 10])
      |> to(:filter)
      |> via_in(:input, buffer: [preferred_size: 10])
      |> to(:consumer)
    ]

    spec = %Membrane.ParentSpec{
      children: children,
      links: links
    }

    {{:ok, spec: spec}, %{}}
  end
end
