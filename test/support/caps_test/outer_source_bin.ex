defmodule Membrane.Support.CapsTest.OuterSourceBin do
  @moduledoc """
  Bin used in caps test.
  It has a caps pattern defined for the `:output` pad.
  Spawns `Membrane.Support.CapsTest.InnerSourceBin` as its child.
  """

  use Membrane.Bin

  alias Membrane.Support.CapsTest
  alias Membrane.Support.CapsTest.Stream
  alias Membrane.Support.CapsTest.Stream.{FormatAcceptedByAll, FormatAcceptedByOuterBins}

  def_output_pad :output,
    demand_unit: :buffers,
    caps_pattern:
      %Stream{format: format} when format in [FormatAcceptedByAll, FormatAcceptedByOuterBins]

  def_options test_pid: [type: :pid]

  @impl true
  def handle_init(%__MODULE__{test_pid: test_pid}) do
    spec = %Membrane.ChildrenSpec{
      structure: [
        child(:inner_source_bin, %CapsTest.InnerSourceBin{test_pid: test_pid})
        |> bin_output()
      ]
    }

    {{:ok, spec: spec}, %{}}
  end

  @impl true
  def handle_parent_notification(msg, _ctx, state) do
    {{:ok, notify_child: {:inner_source_bin, msg}}, state}
  end
end
