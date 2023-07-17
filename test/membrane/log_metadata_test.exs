defmodule Membrane.LogMetadataTest do
  use ExUnit.Case, async: true

  import Membrane.Testing.Assertions

  alias Membrane.Support.LogMetadataTest
  alias Membrane.Testing

  test "Custom log metadata are delivered to the correct element" do
    metadata_1 = "Metadata 1"
    metadata_2 = "Metadata 2"

    assert pipeline_pid =
             Testing.Pipeline.start_link_supervised!(
               module: LogMetadataTest.Pipeline,
               custom_args: %{elements: [element_1: metadata_1, element_2: metadata_2]}
             )

    assert_pipeline_notified(pipeline_pid, :element_1,
      mb_prefix: _mb_prefix,
      test: ^metadata_1
    )

    assert_pipeline_notified(pipeline_pid, :element_2,
      mb_prefix: _mb_prefix,
      test: ^metadata_2
    )
  end
end
