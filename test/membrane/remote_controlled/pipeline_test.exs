defmodule Membrane.RemoteControlled.PipelineTest do
  use ExUnit.Case

  require Membrane.RemoteControlled.Pipeline

  alias Membrane.RemoteControlled.Pipeline
  alias Membrane.ParentSpec

  test "test" do
    {:ok, pipeline} = Pipeline.start_link()

    children = [
      a: %Membrane.Testing.Source{output: [0xA1, 0xB2, 0xC3, 0xD4]},
      b: Membrane.Testing.Sink
    ]

    links = [ParentSpec.link(:a) |> ParentSpec.to(:b)]
    actions = [{:spec, %ParentSpec{children: children, links: links}}]

    Pipeline.exec_actions(pipeline, actions)
    Pipeline.subscribe(pipeline, {:playback_state, _})
    Pipeline.play(pipeline)

    Pipeline.await({:playback_state, state})

    assert state == :prepared

    Pipeline.await({:playback_state, state})

    assert state == :playing

    Pipeline.stop(pipeline)
    Pipeline.await({:playback_state, :stopped})
  end
end
