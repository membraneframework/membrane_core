defmodule Membrane.PipelineTest do
  use ExUnit.Case, async: true

  alias Membrane.Support.TrivialPipeline

  describe "Membrane.Pipeline.start_link/3 should" do
    test "return alive pid when starting a module implementing Membrane.Pipeline behaviour" do
      assert {:ok, supervisor_pid, pipeline_pid} = Membrane.Pipeline.start_link(TrivialPipeline)
      assert is_pid(supervisor_pid) == true
      assert is_pid(pipeline_pid) == true
      assert Process.alive?(supervisor_pid) == true
      assert Process.alive?(pipeline_pid) == true
      this_process_info = :erlang.process_info(self())
      supervisor_info = :erlang.process_info(supervisor_pid)
      pipeline_info = :erlang.process_info(pipeline_pid)
      assert self() in supervisor_info[:links]
      assert supervisor_pid in this_process_info[:links]
      assert pipeline_pid in supervisor_info[:links]
      assert supervisor_pid in pipeline_info[:links]
    end

    test "return error tuple when starting a module that doesn't implement Membrane.Pipeline behaviour" do
      assert Membrane.Pipeline.start_link(NotAPipeline) == {:error, {:not_pipeline, NotAPipeline}}
    end
  end

  describe "Pipeline.start/3 should" do
    test "return alive pid when starting a module implementing Membrane.Pipeline behaviour" do
      assert {:ok, supervisor_pid, pipeline_pid} = Membrane.Pipeline.start(TrivialPipeline)
      assert is_pid(supervisor_pid) == true
      assert is_pid(pipeline_pid) == true
      assert Process.alive?(supervisor_pid) == true
      assert Process.alive?(pipeline_pid) == true
      this_process_info = :erlang.process_info(self())
      supervisor_info = :erlang.process_info(supervisor_pid)
      pipeline_info = :erlang.process_info(pipeline_pid)
      assert self() not in supervisor_info[:links]
      assert supervisor_pid not in this_process_info[:links]
      assert pipeline_pid in supervisor_info[:links]
      assert supervisor_pid in pipeline_info[:links]
    end

    test "return error tuple when starting a module that doesn't implement Membrane.Pipeline behaviour" do
      assert Membrane.Pipeline.start(NotAPipeline) == {:error, {:not_pipeline, NotAPipeline}}
    end
  end
end
