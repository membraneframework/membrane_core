defmodule Membrane.Testing.PipelineTest do
  use ExUnit.Case

  alias Membrane.ParentSpec
  alias Membrane.Testing.Pipeline

  defmodule MockPipeline do
    use Membrane.Pipeline

    @impl true
    def handle_init(_opts), do: {{:ok, spec: %Membrane.ParentSpec{}}, :state}
  end

  describe "Testing pipeline creation" do
    test "works with :default implementation" do
      import ParentSpec
      elements = [elem: Elem, elem2: Elem]
      links = [link(:elem) |> to(:elem2)]
      options = %{module: :default, children: elements, links: links, test_process: nil}
      assert {{:ok, spec: spec}, state} = Pipeline.handle_init(options)
      assert state == %Pipeline.State{module: nil, test_process: nil}

      assert spec == %Membrane.ParentSpec{
               links: links,
               children: elements
             }
    end

    test "by default chooses :default implementation" do
      import ParentSpec
      elements = [elem: Elem, elem2: Elem]
      links = [link(:elem) |> to(:elem2)]
      options = %{module: :default, children: elements, links: links, test_process: nil}
      assert {{:ok, spec: spec}, state} = Pipeline.handle_init(options)
      assert state == %Pipeline.State{module: nil, test_process: nil}

      assert spec == %Membrane.ParentSpec{
               links: links,
               children: elements
             }
    end

    test "works with custom module injected" do
      options = %{module: MockPipeline, test_process: nil, custom_args: []}
      assert {{:ok, spec: spec}, state} = Pipeline.handle_init(options)
      assert spec == %Membrane.ParentSpec{}

      assert state == %Pipeline.State{
               custom_pipeline_state: :state,
               module: MockPipeline,
               test_process: nil
             }
    end
  end

  describe "When initializing Testing Pipeline" do
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

  describe "When starting, Testing Pipeline" do
    test "raises an error if non-existing module was passed" do
      assert_raise RuntimeError, ~r/Not a module./, fn ->
        Pipeline.start(module: [1, 2])
      end

      assert_raise RuntimeError, ~r/Unknown module./, fn ->
        Pipeline.start(module: NotExistingModule)
      end
    end
  end
end
