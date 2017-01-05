defmodule Membrane.ElementSpec do
  use ESpec, async: false

  require Membrane.Support.Element.TrivialSource
  require Membrane.Support.Element.TrivialSink
  require Membrane.Support.Element.TrivialFilter

  alias Membrane.Support.Element.TrivialSource
  alias Membrane.Support.Element.TrivialSink
  alias Membrane.Support.Element.TrivialFilter

  alias Membrane.ElementState


  pending ".start_link/3"
  pending ".start/3"


  xdescribe ".get_module/1" do
    context "if given pid is for element process" do
      let_ok :server, do: Membrane.Element.start(module, %{})
      finally do: Process.exit(server, :kill)

      context "if given pid is a source element" do
        let :module, do: TrivialSource

        it "should return an ok result" do
          expect(described_module.get_module(server)).to be_ok_result
        end

        it "should return a module that was used to spawn the process" do
          {:ok, returned_module} = described_module.get_module(server)
          expect(returned_module).to eq module
        end
      end

      context "if given pid is a sink element" do
        let :module, do: TrivialSink

        it "should return an ok result" do
          expect(described_module.get_module(server)).to be_ok_result
        end

        it "should return a module that was used to spawn the process" do
          {:ok, returned_module} = described_module.get_module(server)
          expect(returned_module).to eq module
        end
      end

      context "if given pid is a filter element" do
        let :module, do: TrivialFilter

        it "should return an ok result" do
          expect(described_module.get_module(server)).to be_ok_result
        end

        it "should return a module that was used to spawn the process" do
          {:ok, returned_module} = described_module.get_module(server)
          expect(returned_module).to eq module
        end
      end
    end

    context "if given pid is not for element process" do
      it "should return an error result" do
        expect(described_module.get_module(self())).to be_error_result
      end

      it "should return :invalid as a reason" do
        {:error, reason} = described_module.get_module(self())
        expect(reason).to eq :invalid
      end
    end
  end


  xdescribe ".get_module!/1" do
    context "if given pid is for element process" do
      let_ok :server, do: Membrane.Element.start(module, %{})
      finally do: Process.exit(server, :kill)

      context "if given pid is a source element" do
        let :module, do: TrivialSource

        it "should return a module that was used to spawn the process" do
          expect(described_module.get_module!(server)).to eq module
        end
      end

      context "if given pid is a sink element" do
        let :module, do: TrivialSink

        it "should return a module that was used to spawn the process" do
          expect(described_module.get_module!(server)).to eq module
        end
      end

      context "if given pid is a filter element" do
        let :module, do: TrivialFilter

        it "should return a module that was used to spawn the process" do
          expect(described_module.get_module!(server)).to eq module
        end
      end
    end

    context "if given pid is not for element process" do
      it "should return :invalid as a reason" do
        expect(fn -> described_module.get_module!(self()) end).to throw_term(:invalid)
      end
    end
  end


  xdescribe ".is_source?/1" do
    context "if given element is a source" do
      let :module, do: TrivialSource

      it "should return true" do
        expect(described_module.is_source?(module)).to be_true
      end
    end

    context "if given element is a filter" do
      let :module, do: TrivialFilter

      it "should return true" do
        expect(described_module.is_source?(module)).to be_true
      end
    end

    context "if given element is a sink" do
      let :module, do: TrivialSink

      it "should return false" do
        expect(described_module.is_source?(module)).to be_false
      end
    end
  end


  xdescribe ".is_sink?/1" do
    context "if given element is a source" do
      let :module, do: TrivialSource

      it "should return false" do
        expect(described_module.is_sink?(module)).to be_false
      end
    end

    context "if given element is a filter" do
      let :module, do: TrivialFilter

      it "should return true" do
        expect(described_module.is_sink?(module)).to be_true
      end
    end

    context "if given element is a sink" do
      let :module, do: TrivialSink

      it "should return true" do
        expect(described_module.is_sink?(module)).to be_true
      end
    end
  end


  pending ".prepare/2"
  pending ".play/2"
  pending ".stop/2"
  pending ".set_message_bus/3"
  pending ".clear_message_bus/2"


  xdescribe ".link/2" do
    context "if first given PID is not a PID of an element process" do
      let :server, do: self()

      let_ok :destination, do: Membrane.Element.start(TrivialSink, %{})
      finally do: Process.exit(destination, :kill)

      it "should return an error result" do
        expect(described_module.link({server, :source}, {destination, :sink})).to be_error_result
      end

      it "should return :invalid_element as a reason" do
        {:error, reason} = described_module.link({server, :source}, {destination, :sink})
        expect(reason).to eq :invalid_element
      end
    end

    context "if second given PID is not a PID of an element process" do
      let_ok :server, do: Membrane.Element.start(TrivialSink, %{})
      finally do: Process.exit(server, :kill)

      let :destination, do: self()

      it "should return an error result" do
        expect(described_module.link({server, :source}, {destination, :sink})).to be_error_result
      end

      it "should return :invalid_element as a reason" do
        {:error, reason} = described_module.link({server, :source}, {destination, :sink})
        expect(reason).to eq :invalid_element
      end
    end


    context "if both given PIDs are equal" do
      let :server, do: self()
      let :destination, do: self()

      it "should return an error result" do
        expect(described_module.link({server, :source}, {destination, :sink})).to be_error_result
      end

      it "should return :loop as a reason" do
        {:error, reason} = described_module.link({server, :source}, {destination, :sink})
        expect(reason).to eq :loop
      end
    end


    context "if both given PIDs are PIDs of element processes" do
      let_ok :server, do: Membrane.Element.start(server_module, %{})
      finally do: Process.exit(server, :kill)

      let_ok :destination, do: Membrane.Element.start(destination_module, %{})
      finally do: Process.unlink(destination)

      context "but first given PID is not a source" do
        let :server_module, do: TrivialSink
        let :destination_module, do: TrivialSink

        it "should return an error result" do
          expect(described_module.link({server, :source}, {destination, :sink})).to be_error_result
        end

        it "should return :invalid_direction as a reason" do
          {:error, reason} = described_module.link({server, :source}, {destination, :sink})
          expect(reason).to eq :invalid_direction
        end
      end

      context "but second given PID is not a sink" do
        let :server_module, do: TrivialSource
        let :destination_module, do: TrivialSource

        it "should return an error result" do
          expect(described_module.link({server, :source}, {destination, :sink})).to be_error_result
        end

        it "should return :invalid_direction as a reason" do
          {:error, reason} = described_module.link({server, :source}, {destination, :sink})
          expect(reason).to eq :invalid_direction
        end
      end

      context "and first given PID is a source and second given PID is a sink" do
        let :server_module, do: TrivialSource
        let :destination_module, do: TrivialSink

        # TODO check if pads are present
        # TODO check if pads match at all
        # TODO check if pads are not already linked
      end
    end
  end


  pending ".link/3"


  describe ".handle_call/3" do
    context "if message is :membrane_play" do
      let :message, do: :membrane_play
      let :module, do: TrivialFilter
      let :internal_state, do: %{}
      let :state, do: %ElementState{module: module, playback_state: playback_state, internal_state: internal_state}

      context "and current playback state is :stopped" do
        let :playback_state, do: :stopped

        pending "and at least one of the callbacks has returned an error"

        context "and all callbacks have returned {:ok, state}" do
          before do
            allow(module).to accept(:handle_play, fn(internal_state) -> {:ok, internal_state} end)
            allow(module).to accept(:handle_prepare, fn(_previous_playback_state, internal_state) -> {:ok, internal_state} end)
            allow(module).to accept(:handle_stop, fn(internal_state) -> {:ok, internal_state} end)
          end

          it "should not call handle_stop callback on element's module" do
            described_module.handle_call(message, self(), state)
            expect(module).to_not accepted(:handle_stop)
          end

          it "should call handle_prepare(:stopped, internal_state) callback on element's module" do
            described_module.handle_call(message, self(), state)
            expect(module).to accepted(:handle_prepare, [:stopped, internal_state])
          end

          it "should call handle_play(internal_state) callback on element's module" do
            described_module.handle_call(message, self(), state)
            expect(module).to accepted(:handle_play, [internal_state])
          end

          pending "should return {:reply, :ok, state} with element state updated"

          it "should return {:reply, :ok, state} with playback state set to :playing" do
            expect(described_module.handle_call(message, self(), state)).to eq {:reply, :ok, %{state | playback_state: :playing}}
          end
        end
      end


      context "and current playback state is :prepared" do
        let :playback_state, do: :prepared

        pending "and at least one of the callbacks has returned an error"

        context "and all callbacks have returned {:ok, state}" do
          before do
            allow(module).to accept(:handle_play, fn(internal_state) -> {:ok, internal_state} end)
            allow(module).to accept(:handle_prepare, fn(_previous_playback_state, internal_state) -> {:ok, internal_state} end)
            allow(module).to accept(:handle_stop, fn(internal_state) -> {:ok, internal_state} end)
          end

          it "should not call handle_stop callback on element's module" do
            described_module.handle_call(message, self(), state)
            expect(module).to_not accepted(:handle_stop)
          end

          it "should not call handle_prepare callback on element's module" do
            described_module.handle_call(message, self(), state)
            expect(module).to_not accepted(:handle_prepare)
          end

          it "should call handle_play(internal_state) callback on element's module" do
            described_module.handle_call(message, self(), state)
            expect(module).to accepted(:handle_play, [internal_state])
          end

          pending "should return {:reply, :ok, state} with element state updated"

          it "should return {:reply, :ok, state} with playback state set to :playing" do
            expect(described_module.handle_call(message, self(), state)).to eq {:reply, :ok, %{state | playback_state: :playing}}
          end
        end
      end


      context "and current playback state is :playing" do
        let :playback_state, do: :playing

        before do
          allow(module).to accept(:handle_play, fn(internal_state) -> {:ok, internal_state} end)
          allow(module).to accept(:handle_prepare, fn(_previous_playback_state, internal_state) -> {:ok, internal_state} end)
          allow(module).to accept(:handle_stop, fn(internal_state) -> {:ok, internal_state} end)
        end

        it "should not call handle_stop callback on element's module" do
          described_module.handle_call(message, self(), state)
          expect(module).to_not accepted(:handle_stop)
        end

        it "should not call handle_prepare callback on element's module" do
          described_module.handle_call(message, self(), state)
          expect(module).to_not accepted(:handle_prepare)
        end

        it "should not call handle_play callback on element's module" do
          described_module.handle_call(message, self(), state)
          expect(module).to_not accepted(:handle_play)
        end

        it "should return {:reply, :noop, state} with unmodified state" do
          expect(described_module.handle_call(message, self(), state)).to eq {:reply, :noop, state}
        end
      end
    end

    context "if message is :membrane_prepare" do
      let :message, do: :membrane_prepare
      let :module, do: TrivialFilter
      let :internal_state, do: %{}
      let :state, do: %ElementState{module: module, playback_state: playback_state, internal_state: internal_state}

      context "and current playback state is :stopped" do
        let :playback_state, do: :stopped

        pending "and at least one of the callbacks has returned an error"

        context "and all callbacks have returned {:ok, state}" do
          before do
            allow(module).to accept(:handle_play, fn(internal_state) -> {:ok, internal_state} end)
            allow(module).to accept(:handle_prepare, fn(_previous_playback_state, internal_state) -> {:ok, internal_state} end)
            allow(module).to accept(:handle_stop, fn(internal_state) -> {:ok, internal_state} end)
          end

          it "should not call handle_stop callback on element's module" do
            described_module.handle_call(message, self(), state)
            expect(module).to_not accepted(:handle_stop)
          end

          it "should call handle_prepare(:stopped, internal_state) callback on element's module" do
            described_module.handle_call(message, self(), state)
            expect(module).to accepted(:handle_prepare, [:stopped, internal_state])
          end

          it "should not call handle_play callback on element's module" do
            described_module.handle_call(message, self(), state)
            expect(module).to_not accepted(:handle_play)
          end

          pending "should return {:reply, :ok, state} with element state updated"

          it "should return {:reply, :ok, state} with playback state set to :prepared" do
            expect(described_module.handle_call(message, self(), state)).to eq {:reply, :ok, %{state | playback_state: :prepared}}
          end
        end
      end


      context "and current playback state is :prepared" do
        let :playback_state, do: :prepared

        before do
          allow(module).to accept(:handle_play, fn(internal_state) -> {:ok, internal_state} end)
          allow(module).to accept(:handle_prepare, fn(_previous_playback_state, internal_state) -> {:ok, internal_state} end)
          allow(module).to accept(:handle_stop, fn(internal_state) -> {:ok, internal_state} end)
        end

        it "should not call handle_stop callback on element's module" do
          described_module.handle_call(message, self(), state)
          expect(module).to_not accepted(:handle_stop)
        end

        it "should not call handle_prepare callback on element's module" do
          described_module.handle_call(message, self(), state)
          expect(module).to_not accepted(:handle_prepare)
        end

        it "should not call handle_play callback on element's module" do
          described_module.handle_call(message, self(), state)
          expect(module).to_not accepted(:handle_play)
        end

        it "should return {:reply, :noop, state} with unmodified state" do
          expect(described_module.handle_call(message, self(), state)).to eq {:reply, :noop, state}
        end
      end


      context "and current playback state is :playing" do
        let :playback_state, do: :playing

        pending "and at least one of the callbacks has returned an error"

        context "and all callbacks have returned {:ok, state}" do
          before do
            allow(module).to accept(:handle_play, fn(internal_state) -> {:ok, internal_state} end)
            allow(module).to accept(:handle_prepare, fn(_previous_playback_state, internal_state) -> {:ok, internal_state} end)
            allow(module).to accept(:handle_stop, fn(internal_state) -> {:ok, internal_state} end)
          end

          it "should not call handle_stop callback on element's module" do
            described_module.handle_call(message, self(), state)
            expect(module).to_not accepted(:handle_stop)
          end

          it "should call handle_prepare(:playing, internal_state) callback on element's module" do
            described_module.handle_call(message, self(), state)
            expect(module).to accepted(:handle_prepare, [:playing, internal_state])
          end

          it "should not call handle_play callback on element's module" do
            described_module.handle_call(message, self(), state)
            expect(module).to_not accepted(:handle_play)
          end

          pending "should return {:reply, :ok, state} with element state updated"

          it "should return {:reply, :ok, state} with playback state set to :prepared" do
            expect(described_module.handle_call(message, self(), state)).to eq {:reply, :ok, %{state | playback_state: :prepared}}
          end
        end
      end
    end

    context "if message is :membrane_stop" do
      let :message, do: :membrane_stop
      let :module, do: TrivialFilter
      let :internal_state, do: %{}
      let :state, do: %ElementState{module: module, playback_state: playback_state, internal_state: internal_state}

      context "and current playback state is :playing" do
        let :playback_state, do: :playing

        pending "and at least one of the callbacks has returned an error"

        context "and all callbacks have returned {:ok, state}" do
          before do
            allow(module).to accept(:handle_play, fn(internal_state) -> {:ok, internal_state} end)
            allow(module).to accept(:handle_prepare, fn(_previous_playback_state, internal_state) -> {:ok, internal_state} end)
            allow(module).to accept(:handle_stop, fn(internal_state) -> {:ok, internal_state} end)
          end

          it "should call handle_stop callback on element's module" do
            described_module.handle_call(message, self(), state)
            expect(module).to accepted(:handle_stop, [internal_state])
          end

          it "should call handle_prepare(:playing, internal_state) callback on element's module" do
            described_module.handle_call(message, self(), state)
            expect(module).to accepted(:handle_prepare, [:playing, internal_state])
          end

          it "should not call handle_play callback on element's module" do
            described_module.handle_call(message, self(), state)
            expect(module).to_not accepted(:handle_play)
          end

          pending "should return {:reply, :ok, state} with element state updated"

          it "should return {:reply, :ok, state} with playback state set to :stopped" do
            expect(described_module.handle_call(message, self(), state)).to eq {:reply, :ok, %{state | playback_state: :stopped}}
          end
        end
      end


      context "and current playback state is :prepared" do
        let :playback_state, do: :prepared

        pending "and at least one of the callbacks has returned an error"

        context "and all callbacks have returned {:ok, state}" do
          before do
            allow(module).to accept(:handle_play, fn(internal_state) -> {:ok, internal_state} end)
            allow(module).to accept(:handle_prepare, fn(_previous_playback_state, internal_state) -> {:ok, internal_state} end)
            allow(module).to accept(:handle_stop, fn(internal_state) -> {:ok, internal_state} end)
          end

          it "should call handle_stop callback on element's module" do
            described_module.handle_call(message, self(), state)
            expect(module).to accepted(:handle_stop, [internal_state])
          end

          it "should not call handle_prepare callback on element's module" do
            described_module.handle_call(message, self(), state)
            expect(module).to_not accepted(:handle_prepare)
          end

          it "should not call handle_play callback on element's module" do
            described_module.handle_call(message, self(), state)
            expect(module).to_not accepted(:handle_play)
          end

          pending "should return {:reply, :ok, state} with element state updated"

          it "should return {:reply, :ok, state} with playback state set to :stopped" do
            expect(described_module.handle_call(message, self(), state)).to eq {:reply, :ok, %{state | playback_state: :stopped}}
          end
        end
      end


      context "and current playback state is :stopped" do
        let :playback_state, do: :stopped

        before do
          allow(module).to accept(:handle_play, fn(internal_state) -> {:ok, internal_state} end)
          allow(module).to accept(:handle_prepare, fn(_previous_playback_state, internal_state) -> {:ok, internal_state} end)
          allow(module).to accept(:handle_stop, fn(internal_state) -> {:ok, internal_state} end)
        end

        it "should not call handle_stop callback on element's module" do
          described_module.handle_call(message, self(), state)
          expect(module).to_not accepted(:handle_stop)
        end

        it "should not call handle_prepare callback on element's module" do
          described_module.handle_call(message, self(), state)
          expect(module).to_not accepted(:handle_prepare)
        end

        it "should not call handle_play callback on element's module" do
          described_module.handle_call(message, self(), state)
          expect(module).to_not accepted(:handle_play)
        end

        it "should return {:reply, :noop, state} with unmodified state" do
          expect(described_module.handle_call(message, self(), state)).to eq {:reply, :noop, state}
        end
      end
    end

    pending "if message is {:membrane_set_message_bus, pid}"
    pending "if message is :membrane_clear_message_bus"
  end
end
