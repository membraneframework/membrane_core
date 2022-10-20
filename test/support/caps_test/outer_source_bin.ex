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
    caps: %Stream{format: format} when format in [FormatAcceptedByAll, FormatAcceptedByOuterBins]

  def_options test_pid: [type: :pid],
              caps: [type: :any]

  @impl true
  def handle_init(%__MODULE__{test_pid: test_pid, caps: caps}) do
    spec = %Membrane.ChildrenSpec{
      structure: [
        child(:inner_source_bin, %CapsTest.InnerSourceBin{test_pid: test_pid, caps: caps})
        |> bin_output()
      ]
    }

    {{:ok, spec: spec}, %{}}
  end
end
