defmodule Membrane.Support.CapsTest.InnerSourceBin do
  @moduledoc """
  Bin used in caps test.
  Has caps pattern for `:output` pad.
  Spawns `Membrane.Support.CapsTest.Source` as its child.
  """

  use Membrane.Bin

  alias Membrane.Support.CapsTest
  alias Membrane.Support.CapsTest.Stream
  alias Membrane.Support.CapsTest.Stream.{FormatAcceptedByAll, FormatAcceptedByInnerBins}

  def_output_pad :output,
    demand_unit: :buffers,
    caps_pattern:
      %Stream{format: format} when format in [FormatAcceptedByAll, FormatAcceptedByInnerBins]

  def_options test_pid: [type: :pid]

  @impl true
  def handle_init(%__MODULE__{test_pid: test_pid}) do
    spec = %Membrane.ChildrenSpec{
      structure: [
        child(:source, %CapsTest.Source{test_pid: test_pid})
        |> bin_output()
      ]
    }

    {{:ok, spec: spec}, %{}}
  end

  @impl true
  def handle_parent_notification(msg, _ctx, state) do
    {{:ok, notify_child: {:source, msg}}, state}
  end
end
