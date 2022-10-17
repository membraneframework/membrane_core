defmodule Membrane.Support.CapsTest.InnerSinkBin do
  @moduledoc """
  Bin used in caps test.
  Has caps pattern for `:input` pad.
  Spawns `Membrane.Support.CapsTest.Sink` as its child.
  """

  use Membrane.Bin

  alias Membrane.Support.CapsTest
  alias Membrane.Support.CapsTest.Stream
  alias Membrane.Support.CapsTest.Stream.{FormatAcceptedByAll, FormatAcceptedByInnerBins}

  def_input_pad :input,
    demand_unit: :buffers,
    caps_pattern:
      %Stream{format: format} when format in [FormatAcceptedByAll, FormatAcceptedByInnerBins],
    availability: :always,
    mode: :push

  def_options test_pid: [type: :pid]

  @impl true
  def handle_init(%__MODULE__{test_pid: test_pid}) do
    spec = %Membrane.ChildrenSpec{
      structure: [
        bin_input()
        |> child(:sink, %CapsTest.Sink{test_pid: test_pid})
      ]
    }

    {{:ok, spec: spec}, %{}}
  end

  @impl true
  def handle_child_notification(msg, _child, _ctx, state) do
    {{:ok, notify_parent: msg}, state}
  end
end
