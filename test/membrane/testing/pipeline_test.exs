defmodule Membrane.Testing.PipelineTest do
  use ExUnit.Case

  alias Membrane.ParentSpec
  alias Membrane.Testing.Pipeline

  defmodule MockPipeline do
    use Membrane.Pipeline

    @impl true
    def handle_init(_opts), do: {{:ok, spec: %Membrane.ParentSpec{}}, :state}
  end

  describe "When initializing Testing Pipeline" do
    test "generates links if only elements were provided" do
      import ParentSpec
      elements = [elem: Elem, elem2: Elem]
      links = [link(:elem) |> to(:elem2)]
      options = %Pipeline.Options{children: elements}
      assert {{:ok, spec: spec}, state} = Pipeline.handle_init(options)
      assert state == %Pipeline.State{module: nil, test_process: nil}

      assert spec == %Membrane.ParentSpec{
               links: links,
               children: elements
             }
    end

    test "uses prepared links if they were provided" do
      import ParentSpec
      elements = [elem: Elem, elem2: Elem]
      links = link(:elem) |> to(:elem2)
      options = %Pipeline.Options{children: elements, links: links}
      assert {{:ok, spec: spec}, state} = Pipeline.handle_init(options)
      assert state == %Pipeline.State{module: nil, test_process: nil}

      assert spec == %Membrane.ParentSpec{
               links: links,
               children: elements
             }
    end

    test "if no elements nor links were provided uses module's callback" do
      options = %Pipeline.Options{module: MockPipeline}
      assert {{:ok, spec: spec}, state} = Pipeline.handle_init(options)
      assert spec == %Membrane.ParentSpec{}

      assert state == %Pipeline.State{
               custom_pipeline_state: :state,
               module: MockPipeline,
               test_process: nil
             }
    end
  end

  describe "When starting Testing Pipeline" do
    test "raises an error if unknown testing pipeline mode was passed" do
      assert_raise RuntimeError, ~r/Unknown testing pipeline mode./, fn ->
        Pipeline.start(mode: :unknown)
      end
    end

    test "raises an error if no testing pipeline mode was passed" do
      assert_raise KeyError, ~r/key :mode not found in./, fn ->
        Pipeline.start(children: nil)
      end
    end

  end
end
