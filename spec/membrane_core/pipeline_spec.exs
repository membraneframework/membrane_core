defmodule Membrane.PipelineSpec do
  use ESpec, async: false
  alias Membrane.Support.Element.TrivialPipeline

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

      it "should return pid of the process that is linked in the supervision tree" do
        {:ok, pid} = described_module().start_link(module(), options(), process_options())
        {:links, links} = :erlang.process_info(pid, :links)
        expect(length(links)) |> to(eq(1))
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

      it "should return pid of the process that is  not linked in the supervision tree" do
        {:ok, pid} = described_module().start(module(), options(), process_options())
        {:links, links} = :erlang.process_info(pid, :links)
        expect(length(links)) |> to(eq(0))
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

  describe ".is_pipeline?/1" do
    context "when module is a pipeline" do
      let :module, do: TrivialPipeline

      it "should return true" do
        expect(described_module().is_pipeline?(module())) |> to(be_true())
      end
    end

    context "when module is not a pipeline" do
      let :module, do: Membrane.Support.Element.TrivialSource

      it "should return false" do
        expect(described_module().is_pipeline?(module())) |> to(be_false())
      end

      it "should return false" do
        expect(described_module().is_pipeline?(Enum)) |> to(be_false())
      end
    end
  end

  describe ".init/1" do
    let :module, do: TrivialPipeline
    let :options, do: nil

    before do
      allow TrivialPipeline |> to(accept(:handle_init, fn arg -> :meck.passthrough([arg]) end))
    end

    it "should return an ok result" do
      ret = described_module().init({module(), options()})
      expect(ret) |> to(be_ok_result())
    end

    it "should return {:ok, %Pipeline.State{}} tuple" do
      {:ok, state} = described_module().init({module(), options()})
      expect(state.__struct__) |> to(eq(Membrane.Pipeline.State))
    end

    it "should return state containing correct module" do
      {:ok, state} = described_module().init({module(), options()})
      expect(state.module) |> to(eq(TrivialPipeline))
    end

    it "should return pipeline that is stopped" do
      {:ok, state} = described_module().init({module(), options()})
      expect(state.playback.state) |> to(eq(:stopped))
    end

    it "should send a message to initialize children asynchronously" do
      described_module().init({module(), options()})
      assert_received [:membrane_pipeline_spec, _]
    end

    it "should call pipeline's handle_init" do
      described_module().init({module(), options()})
      expect(TrivialPipeline |> to(accepted(:handle_init)))
    end
  end

  describe ".handle_info/2" do
    let :module, do: TrivialPipeline
    let :options, do: nil
    let! :state, do: described_module().init({module(), options()}) |> elem(1)
    let :sample_element, do: Membrane.Support.Element.TrivialSource

    before do
      allow Membrane.Element
            |> to(
              accept(:link, fn a1, a2, a3, a4, a5 -> :meck.passthrough([a1, a2, a3, a4, a5]) end)
            )

      allow sample_element() |> to(accept(:handle_init, fn arg -> :meck.passthrough([arg]) end))

      allow module()
            |> to(accept(:handle_message, fn arg1, arg2 -> :meck.passthrough([arg1, arg2]) end))
    end

    context "when receiving message with pipeline spec" do
      let :init_result, do: TrivialPipeline.handle_init(nil)
      let :spec, do: init_result() |> elem(0) |> elem(1)
      let :internal_state, do: init_result() |> elem(1)
      let :message, do: [:membrane_pipeline_spec, spec()]
      let :links_number, do: length(spec().links |> Map.keys())

      it "should return :noreply response" do
        {atom, _state} = described_module().handle_info(message(), state())
        expect(atom) |> to(eq(:noreply))
      end

      it "should return new pipeline state" do
        {:noreply, state} = described_module().handle_info(message(), state())
        expect(state.__struct__) |> to(eq(Membrane.Pipeline.State))
      end

      it "should return new pipeline state containing map with pids for every child" do
        {:noreply, state} = described_module().handle_info(message(), state())

        expect(state.children_to_pids |> Map.keys() |> Enum.sort())
        |> to(eq(spec().children |> Keyword.keys() |> Enum.sort()))
      end

      it "should return new pipeline state containing state" do
        {:noreply, state} = described_module().handle_info(message(), state())
        expect(state.internal_state) |> to(eq(internal_state()))
      end

      it "should call element's handle_init" do
        described_module().handle_info(message(), state())
        expect(sample_element()) |> to(accepted(:handle_init))
      end

      it "should link elements" do
        described_module().handle_info(message(), state())
        expect(Membrane.Element) |> to(accepted(:link, :any, count: links_number()))
      end
    end

    context "when receiving message from the element" do
      let :child_name, do: :child_name
      let :internal_state, do: :some_internal_state

      let :state,
        do: %Membrane.Pipeline.State{
          pids_to_children: %{self() => child_name()},
          internal_state: internal_state(),
          module: module()
        }

      let :internal_message, do: %Membrane.Message{}
      let! :message, do: [:membrane_message, child_pid(), internal_message()]

      context "when received from child" do
        let :child_pid, do: self()

        it "should return {:noreply, ..} result" do
          {atom, _} = described_module().handle_info(message(), state())
          expect(atom) |> to(eq(:noreply))
        end

        it "should invoke handle_message from pipeline module with correct arguments" do
          described_module().handle_info(message(), state())

          expect(module())
          |> to(accepted(:handle_message, [internal_message(), child_pid(), internal_state()]))
        end

        it "should keep state unchanged" do
          {:noreply, new_state} = described_module().handle_info(message(), state())
          expect(new_state) |> to(eq(state()))
        end
      end

      context "when received from process that is not a child" do
        let :child_pid, do: :c.pid(0, 212, 0)

        it "should return {:stop, _, _}" do
          {atom, _, _} = described_module().handle_info(message(), state())
          expect(atom) |> to(eq(:stop))
        end

        it "should keep state unchanged" do
          {:stop, _, new_state} = described_module().handle_info(message(), state())
          expect(new_state) |> to(eq(state()))
        end

        it "should return error tuple" do
          {:stop, error_tuple, _} = described_module().handle_info(message(), state())
          expect(error_tuple) |> to(be_error_result())
        end

        it "should return :unknown_child as a reason" do
          {:stop, {:error, {atom, _pid}}, _} = described_module().handle_info(message(), state())
          expect(atom) |> to(eq(:unknown_child))
        end

        it "should include given pid in the reason" do
          {:stop, {:error, {_, pid}}, _} = described_module().handle_info(message(), state())
          expect(pid) |> to(eq(child_pid()))
        end
      end
    end

    context "when receiving other message" do
      let :message, do: :some_message
      let :internal_state, do: :some_internal_state
      let :state, do: %Membrane.Pipeline.State{module: module(), internal_state: internal_state()}

      before do
        allow module()
              |> to(accept(:handle_other, fn arg1, arg2 -> :meck.passthrough([arg1, arg2]) end))
      end

      it "should return {:noreply, ..} tuple" do
        {atom, _} = described_module().handle_info(message(), state())
        expect(atom) |> to(eq(:noreply))
      end

      it "should keep state unchanged" do
        {:noreply, new_state} = described_module().handle_info(message(), state())
        expect(new_state) |> to(eq(state()))
      end

      it "should invoke handle_other callback from the pipeline module" do
        described_module().handle_info(message(), state())
        expect(module()) |> to(accepted(:handle_other, [message(), internal_state()]))
      end
    end
  end

  pending("changing playback state -> handle_call?")
end
