defmodule Membrane.PipelineTest do
  use ExUnit.Case, async: true

  alias Membrane.Support.Elements.TrivialFilter, as: NotAPipeline
  alias Membrane.Support.TrivialPipeline

  describe "Membrane.Pipeline.start_link/3 should" do
    test "return alive pid when starting a module implementing Membrane.Pipeline behaviour" do
      {:ok, supervisor_pid, pipeline_pid} = Membrane.Pipeline.start_link(TrivialPipeline)
      assert is_pid(supervisor_pid) == true
      assert is_pid(pipeline_pid) == true
      assert Process.alive?(supervisor_pid) == true
      assert Process.alive?(pipeline_pid) == true
    end

    test "return error tuple when starting a module that doesn't implement Membrane.Pipeline behaviour" do
      {:error, {:not_pipeline, module}} = Membrane.Pipeline.start_link(NotAPipeline)
      assert module == NotAPipeline
    end
  end

  describe "Pipeline.start/3 should" do
    test "return alive pid when starting a module implementing Membrane.Pipeline behaviour" do
      {:ok, supervisor_pid, pipeline_pid} = Membrane.Pipeline.start_link(TrivialPipeline)
      assert is_pid(supervisor_pid) == true
      assert is_pid(pipeline_pid) == true
      assert Process.alive?(supervisor_pid) == true
      assert Process.alive?(pipeline_pid) == true
    end

    test "return error tuple when starting a module that doesn't implement Membrane.Pipeline behaviour" do
      {:error, {:not_pipeline, module}} = Membrane.Pipeline.start_link(NotAPipeline)
      assert module == NotAPipeline
    end
  end
end
