defmodule Membrane.Testing.PipelineTest do
  use ExUnit.Case

  alias Membrane.ParentSpec
  alias Membrane.Testing.Pipeline

  defmodule MockPipeline do
    use Membrane.Pipeline

    @impl true
    def handle_init(_ctx, _opts), do: {{:ok, spec: %Membrane.ParentSpec{}}, :state}
  end

  describe "Testing pipeline creation" do
    test "works with :default implementation" do
      import ParentSpec
      elements = [elem: Elem, elem2: Elem]
      links = [link(:elem) |> to(:elem2)]
      options = [module: :default, children: elements, links: links, test_process: nil]
      assert {{:ok, spec: spec, playback: :playing}, state} = Pipeline.handle_init(%{}, options)

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
      options = [module: :default, children: elements, links: links, test_process: nil]
      assert {{:ok, spec: spec, playback: :playing}, state} = Pipeline.handle_init(%{}, options)
      assert state == %Pipeline.State{module: nil, test_process: nil}

      assert spec == %Membrane.ParentSpec{
               links: links,
               children: elements
             }
    end

    test "works with custom module injected" do
      options = [module: MockPipeline, test_process: nil, custom_args: []]
      assert {{:ok, spec: spec}, state} = Pipeline.handle_init(%{}, options)
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
      options = [module: :default, children: elements, links: links, test_process: nil]
      assert {{:ok, spec: spec, playback: :playing}, state} = Pipeline.handle_init(%{}, options)
      assert state == %Pipeline.State{module: nil, test_process: nil}

      assert spec == %Membrane.ParentSpec{
               links: links,
               children: elements
             }
    end
  end

  describe "When starting, Testing Pipeline" do
    test "exits with an error if not a module or non-existing module was passed" do
      Process.flag(:trap_exit, true)
      Pipeline.start_link(module: [1, 2])
      assert_receive {:EXIT, _pid, {exception, stacktrace}}
      assert_raise RuntimeError, ~r/Not a module./, fn -> reraise exception, stacktrace end
      Pipeline.start_link(module: NotExistingModule)
      assert_receive {:EXIT, _pid, {exception, stacktrace}}
      assert_raise RuntimeError, ~r/Unknown module./, fn -> reraise exception, stacktrace end
    end
  end
end
