defmodule Membrane.PipelineSpec do
  use ESpec, async: false

  alias Membrane.Core.Message
  alias Membrane.Support.Element.TrivialPipeline

  require Message

  describe ".start_link/3" do
    context "when starting `TrivialPipeline`" do
      let :module, do: TrivialPipeline
      let :options, do: nil
      let :process_options, do: []

      it "should return an ok result" do
        expect(described_module().start_link(module(), options(), process_options()))
        |> to(be_ok_result())
      end

      it "should return {:ok, pid}" do
        {:ok, value} = described_module().start_link(module(), options(), process_options())
        expect(value) |> to(be_pid())
      end

      it "should return pid of the process that is alive" do
        {:ok, pid} = described_module().start_link(module(), options(), process_options())
        expect(Process.alive?(pid)) |> to(be_true())
      end
    end

    context "when starting module that is not a pipeline" do
      let :module, do: Membrane.Support.Element.TrivialSource
      let :options, do: nil
      let :process_options, do: []

      it "should return an error result" do
        expect(described_module().start_link(module(), options(), process_options()))
        |> to(be_error_result())
      end

      it "should return tuple {:not_pipeline, module()} as a reason" do
        {:error, value} = described_module().start_link(module(), options(), process_options())
        expect(value) |> to(eq {:not_pipeline, module()})
      end
    end
  end

  describe ".start/3" do
    context "when starting `TrivialPipeline`" do
      let :module, do: TrivialPipeline
      let :options, do: nil
      let :process_options, do: []

      it "should return an ok result" do
        expect(described_module().start(module(), options(), process_options()))
        |> to(be_ok_result())
      end

      it "should return {:ok, pid}" do
        {:ok, value} = described_module().start(module(), options(), process_options())
        expect(value) |> to(be_pid())
      end

      it "should return pid of the process that is alive" do
        {:ok, pid} = described_module().start(module(), options(), process_options())
        expect(Process.alive?(pid)) |> to(be_true())
      end
    end

    context "when starting module that is not a pipeline" do
      let :module, do: Membrane.Support.Element.TrivialSource
      let :options, do: nil
      let :process_options, do: []

      it "should return an error result" do
        expect(described_module().start(module(), options(), process_options()))
        |> to(be_error_result())
      end

      it "should return tuple {:not_pipeline, module()} as a reason" do
        {:error, value} = described_module().start(module(), options(), process_options())
        expect(value) |> to(eq {:not_pipeline, module()})
      end
    end
  end

  describe ".pipeline?/1" do
    context "when module is a pipeline" do
      let :module, do: TrivialPipeline

      it "should return true" do
        expect(described_module().pipeline?(module())) |> to(be_true())
      end
    end

    context "when module is not a pipeline" do
      let :module, do: Membrane.Support.Element.TrivialSource

      it "should return false" do
        expect(described_module().pipeline?(module())) |> to(be_false())
      end

      it "should return false" do
        expect(described_module().pipeline?(Enum)) |> to(be_false())
      end
    end
  end
end
