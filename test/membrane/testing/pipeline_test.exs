defmodule Membrane.Testing.PipelineTest do
  use ExUnit.Case

  alias Membrane.Testing.Pipeline

  defmodule MockPipeline do
    use Membrane.Pipeline

    @impl true
    def handle_init(_opts), do: {{:ok, %Membrane.Pipeline.Spec{}}, :state}
  end

  describe "When initializing Testing Pipeline" do
    test "generates links if only elements were provided" do
      elements = [elem: Elem, elem2: Elem]
      links = %{{:elem, :output} => {:elem2, :input}}
      options = %Pipeline.Options{elements: elements}
      assert {{:ok, spec}, state} = Pipeline.handle_init(options)
      assert state == %Pipeline.State{module: nil, test_process: nil}

      assert spec == %Membrane.Pipeline.Spec{
               links: links,
               children: elements
             }
    end

    test "uses prepared links if they were provided" do
      elements = [elem: Elem, elem2: Elem]
      links = %{{:elem, :output} => {:elem2, :input}}
      options = %Pipeline.Options{elements: elements, links: links}
      assert {{:ok, spec}, state} = Pipeline.handle_init(options)
      assert state == %Pipeline.State{module: nil, test_process: nil}

      assert spec == %Membrane.Pipeline.Spec{
               links: links,
               children: elements
             }
    end

    test "if no elements nor links were provided uses module's callback" do
      options = %Pipeline.Options{module: MockPipeline}
      assert {{:ok, spec}, state} = Pipeline.handle_init(options)
      assert spec == %Membrane.Pipeline.Spec{}

      assert state == %Pipeline.State{
               custom_pipeline_state: :state,
               module: MockPipeline,
               test_process: nil
             }
    end
  end

  describe "When starting Testing Pipeline does" do
    test "returns an error if a pipeline is started with both elements and module provided in options" do
      assert_raise RuntimeError, fn ->
        Pipeline.start(%Pipeline.Options{elements: [elem: Elem], module: Mod})
      end
    end

    test "returns an error if no means of generating spec are provided (no elements, no module)" do
      assert_raise RuntimeError, fn ->
        Pipeline.start(%Pipeline.Options{elements: nil, module: nil})
      end
    end
  end
end
