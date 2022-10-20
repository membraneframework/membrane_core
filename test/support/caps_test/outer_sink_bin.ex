defmodule Membrane.Support.CapsTest.OuterSinkBin do
  @moduledoc """
  Bin used in caps test.
  It has a caps pattern defined for the `:input` pad.
  Spawns `Membrane.Support.CapsTest.InnerSinkBin` as its child.
  """

  use Membrane.Bin

  alias Membrane.Support.CapsTest
  alias Membrane.Support.CapsTest.Stream
  alias Membrane.Support.CapsTest.Stream.{FormatAcceptedByAll, FormatAcceptedByOuterBins}

  def_input_pad :input,
    demand_unit: :buffers,
    caps: %Stream{format: format} when format in [FormatAcceptedByAll, FormatAcceptedByOuterBins],
    availability: :always,
    mode: :push

  def_options test_pid: [type: :pid]

  @impl true
  def handle_init(%__MODULE__{test_pid: test_pid}) do
    spec = %Membrane.ChildrenSpec{
      structure: [
        bin_input()
        |> child(:sink, %CapsTest.InnerSinkBin{test_pid: test_pid})
      ]
    }

    {{:ok, spec: spec}, %{}}
  end

  @impl true
  def handle_child_notification(msg, _child, _ctx, state) do
    {{:ok, notify_parent: msg}, state}
  end
end
