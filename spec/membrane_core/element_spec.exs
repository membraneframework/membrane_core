defmodule Membrane.ElementSpec do
  use ESpec, async: false

  require Membrane.Support.Element.TrivialSource
  require Membrane.Support.Element.TrivialSink
  require Membrane.Support.Element.TrivialFilter

  alias Membrane.Support.Element.TrivialSource
  alias Membrane.Support.Element.TrivialSink
  alias Membrane.Support.Element.TrivialFilter

  alias Membrane.Element.Manager.State

  alias Membrane.Mixins.Playback

  pending ".start_link/3"
  pending ".start/3"
  pending ".get_message_bus/2"
  pending ".clear_message_bus/2"

  describe ".link/5" do
    context "if first given PID is not a PID of an element process" do
      let :server, do: self()
      let :destination, do: :destination

      it "should return an error result" do
        expect(described_module().link(server(), destination(), :source, :sink, []))
        |> to(be_error_result())
      end

      it "should return :invalid_element as a reason" do
        {:error, reason} = described_module().link(server(), destination(), :source, :sink, [])
        expect(reason) |> to(eq :invalid_element)
      end
    end

    context "if second given PID is not a PID of an element process" do
      let_ok :server, do: Membrane.Element.start(self(), TrivialSink, %{})
      finally do: Process.exit(server(), :kill)

      let :destination, do: self()

      it "should return an error result" do
        expect(described_module().link(server(), destination(), :source, :sink, []))
        |> to(be_error_result())
      end

      it "should return :unknown_pad as a reason" do
        {:error, {:handle_call, {:cannot_handle_message, [message: _, mode: _, reason: reason]}}} =
          described_module().link(server(), destination(), :source, :sink, [])

        expect(reason) |> to(eq :unknown_pad)
      end
    end

    context "if both given PIDs are equal" do
      let :server, do: self()
      let :destination, do: self()

      it "should return an error result" do
        expect(described_module().link(server(), destination(), :source, :sink, []))
        |> to(be_error_result())
      end

      it "should return :loop as a reason" do
        {:error, reason} = described_module().link(server(), destination(), :source, :sink, [])
        expect(reason) |> to(eq :loop)
      end
    end

    context "if both given PIDs are PIDs of element processes" do
      let_ok :server, do: Membrane.Element.start(self(), server_module(), %{})
      finally do: Process.exit(server(), :kill)

      let_ok :destination, do: Membrane.Element.start(self(), destination_module(), %{})
      finally do: Process.unlink(destination())

      context "but first given PID is not a source" do
        let :server_module, do: TrivialSink
        let :destination_module, do: TrivialSink

        it "should return an error result" do
          expect(described_module().link(server(), destination(), :source, :sink, []))
          |> to(be_error_result())
        end

        it "should return :invalid_direction as a reason" do
          {:error, val} = described_module().link(server(), destination(), :source, :sink, [])
          {:handle_call, {:cannot_handle_message, [message: _, mode: _, reason: reason]}} = val
          expect(reason) |> to(eq :unknown_pad)
        end
      end

      context "but second given PID is not a sink" do
        let :server_module, do: TrivialSource
        let :destination_module, do: TrivialSource

        it "should return an error result" do
          expect(described_module().link(server(), destination(), :source, :sink, []))
          |> to(be_error_result())
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

  describe ".handle_info/3" do
    context "if message is :membrane_play" do
      let :message, do: {:membrane_change_playback_state, :playing}
      let :module, do: TrivialSource
      let :internal_state, do: %{a: 1}

      let :state,
        do: %State{
          module: module(),
          playback: playback(),
          playback_buffer: Membrane.Element.Manager.PlaybackBuffer.new(),
          internal_state: internal_state()
        }

      context "and current playback state is :stopped" do
        let :playback, do: %Playback{state: :stopped}

        context "and handle_prepare callback has returned an error" do
          let :reason, do: :whatever

          before do
            allow(module()).to(
              accept(:handle_play, fn received_internal_state ->
                {:ok, received_internal_state}
              end)
            )

            allow(module()).to(
              accept(:handle_prepare, fn _previous_playback_state, received_internal_state ->
                {{:error, reason()}, %{received_internal_state | a: 2}}
              end)
            )

            allow(module()).to(
              accept(:handle_stop, fn received_internal_state ->
                {:ok, received_internal_state}
              end)
            )
          end

          it "should not call handle_stop callback on element's module" do
            described_module().handle_info(message(), state())
            expect(module()) |> to_not(accepted(:handle_stop))
          end

          it "should call handle_prepare(:stopped, internal_state) callback on element's module" do
            described_module().handle_info(message(), state())
            expect(module()) |> to(accepted(:handle_prepare, [:stopped, internal_state()]))
          end

          it "should not call handle_play(internal_state) callback on element's module" do
            described_module().handle_info(message(), state())
            expect(module()) |> to_not(accepted(:handle_play))
          end

          it "should return :stop response" do
            {response, _info, _state} = described_module().handle_info(message(), state())
            expect(response) |> to(eq :stop)
          end

          it "should return {:error, reason} as a reply info" do
            {_response, info, _state} = described_module().handle_info(message(), state())
            expect(info) |> to(be_error_result())
          end

          it "should return {:reply, {:error, reason}, state()} with internal state updated" do
            {_response, _info, %State{internal_state: new_internal_state}} =
              described_module().handle_info(message(), state())

            expect(new_internal_state) |> to(eq %{internal_state() | a: 2})
          end

          it "should return {:reply, {:error, reason}, state()} with unchanged playback state" do
            {_response, _info, %State{playback: new_playback}} =
              described_module().handle_info(message(), state())

            expect(new_playback.state) |> to(eq playback().state)
          end
        end

        context "and handle_play callback has returned an error" do
          let :reason, do: :whatever

          before do
            allow(module()).to(
              accept(:handle_play, fn received_internal_state ->
                {:error, reason(), %{received_internal_state | a: 3}}
              end)
            )

            allow(module()).to(
              accept(:handle_prepare, fn _previous_playback_state, internal_state ->
                {:ok, %{internal_state | a: 2}}
              end)
            )

            allow(module()).to(
              accept(:handle_stop, fn received_internal_state ->
                {:ok, received_internal_state}
              end)
            )
          end

          it "should not call handle_stop callback on element's module" do
            described_module().handle_info(message(), state())
            expect(module()) |> to_not(accepted(:handle_stop))
          end

          it "should call handle_prepare(:stopped, internal_state) callback on element's module" do
            described_module().handle_info(message(), state())
            expect(module()) |> to(accepted(:handle_prepare, [:stopped, internal_state()]))
          end

          it "should call handle_play(internal_state) callback on element's module with internal state updated by previous handle_prepare call" do
            described_module().handle_info(message(), state())
            expect(module()) |> to(accepted(:handle_play, [%{internal_state() | a: 2}]))
          end

          # TODO similar to above
        end

        context "and all callbacks have returned {:ok, state()}" do
          let :new_internal_state, do: %{key: :new_value}

          before do
            allow(module()).to(
              accept(:handle_play, fn received_internal_state ->
                {:ok, received_internal_state}
              end)
            )

            allow(module()).to(
              accept(:handle_prepare, fn _previous_playback_state, _received_internal_state ->
                {:ok, new_internal_state()}
              end)
            )

            allow(module()).to(
              accept(:handle_stop, fn received_internal_state ->
                {:ok, received_internal_state}
              end)
            )
          end

          it "should not call handle_stop callback on element's module" do
            described_module().handle_info(message(), state())
            expect(module()) |> to_not(accepted(:handle_stop))
          end

          it "should call handle_prepare(:stopped, internal_state) callback on element's module" do
            described_module().handle_info(message(), state())
            expect(module()) |> to(accepted(:handle_prepare, [:stopped, internal_state()]))
          end

          it "should call handle_play(internal_state) callback on element's module with state updated by handle_prepare" do
            described_module().handle_info(message(), state())
            expect(module()) |> to(accepted(:handle_play, [new_internal_state()]))
          end

          it "it return {:reply, :ok, state()} with internal state updated by handle_prepare" do
            {:noreply, %{internal_state: returned_state}} =
              described_module().handle_info(message(), state())

            expect(returned_state) |> to(eq new_internal_state())
          end

          it "should return {:reply, :ok, state()} with playback state set to :playing" do
            {:noreply, %{playback: returned_playback}} =
              described_module().handle_info(message(), state())

            expect(returned_playback.state) |> to(eq :playing)
          end
        end
      end

      context "and current playback state is :prepared" do
        let :playback, do: %Playback{state: :prepared}

        pending "and at least one of the callbacks has returned an error"

        context "and all callbacks have returned {:ok, state()}" do
          let :new_internal_state, do: :new_state

          before do
            allow(module()).to(accept(:handle_play, fn _state -> {:ok, new_internal_state()} end))

            allow(module()).to(
              accept(:handle_prepare, fn _previous_playback_state, received_internal_state ->
                {:ok, received_internal_state}
              end)
            )

            allow(module()).to(
              accept(:handle_stop, fn received_internal_state ->
                {:ok, received_internal_state}
              end)
            )
          end

          it "should not call handle_stop callback on element's module" do
            described_module().handle_info(message(), state())
            expect(module()) |> to_not(accepted(:handle_stop))
          end

          it "should not call handle_prepare callback on element's module" do
            described_module().handle_info(message(), state())
            expect(module()) |> to_not(accepted(:handle_prepare))
          end

          it "should call handle_play(internal_state) callback on element's module" do
            described_module().handle_info(message(), state())
            expect(module()) |> to(accepted(:handle_play, [internal_state()]))
          end

          it "should return {:reply, :ok, state()} with internal state updated" do
            {:noreply, %{internal_state: returned_state}} =
              described_module().handle_info(message(), state())

            expect(returned_state) |> to(eq new_internal_state())
          end

          it "should return {:reply, :ok, state()} with playback state set to :playing" do
            {:noreply, %{playback: new_playback}} =
              described_module().handle_info(message(), state())

            expect(new_playback.state) |> to(eq :playing)
          end
        end
      end

      context "and current playback state is :playing" do
        let :playback, do: %Playback{state: :playing}

        before do
          allow(module()).to(
            accept(:handle_play, fn received_internal_state -> {:ok, received_internal_state} end)
          )

          allow(module()).to(
            accept(:handle_prepare, fn _previous_playback_state, received_internal_state ->
              {:ok, received_internal_state}
            end)
          )

          allow(module()).to(
            accept(:handle_stop, fn received_internal_state -> {:ok, received_internal_state} end)
          )
        end

        it "should not call handle_stop callback on element's module" do
          described_module().handle_info(message(), state())
          expect(module()) |> to_not(accepted(:handle_stop))
        end

        it "should not call handle_prepare callback on element's module" do
          described_module().handle_info(message(), state())
          expect(module()) |> to_not(accepted(:handle_prepare))
        end

        it "should not call handle_play callback on element's module" do
          described_module().handle_info(message(), state())
          expect(module()) |> to_not(accepted(:handle_play))
        end

        pending "should return {:reply, :noop, state()} with unmodified state"
      end
    end

    context "if message is :membrane_prepare" do
      let :message, do: {:membrane_change_playback_state, :prepared}
      let :module, do: TrivialFilter
      let :internal_state, do: %{}

      let :state,
        do: %State{module: module(), playback: playback(), internal_state: internal_state()}

      context "and current playback state is :stopped" do
        let :playback, do: %Playback{state: :stopped}

        pending "and at least one of the callbacks has returned an error"

        context "and all callbacks have returned {:ok, state()}" do
          let :new_internal_state, do: :new_int_state

          before do
            allow(module()).to(
              accept(:handle_play, fn received_internal_state ->
                {:ok, received_internal_state}
              end)
            )

            allow(module()).to(
              accept(:handle_prepare, fn _previous_playback_state, _state ->
                {:ok, new_internal_state()}
              end)
            )

            allow(module()).to(
              accept(:handle_stop, fn received_internal_state ->
                {:ok, received_internal_state}
              end)
            )
          end

          it "should not call handle_stop callback on element's module" do
            described_module().handle_info(message(), state())
            expect(module()) |> to_not(accepted(:handle_stop))
          end

          it "should call handle_prepare(:stopped, internal_state) callback on element's module" do
            described_module().handle_info(message(), state())
            expect(module()) |> to(accepted(:handle_prepare, [:stopped, internal_state()]))
          end

          it "should not call handle_play callback on element's module" do
            described_module().handle_info(message(), state())
            expect(module()) |> to_not(accepted(:handle_play))
          end

          it "should return {:reply, :ok, state()} with internal state updated" do
            {:noreply, %{internal_state: returned_state}} =
              described_module().handle_info(message(), state())

            expect(returned_state) |> to(eq new_internal_state())
          end

          it "should return {:reply, :ok, state()} with playback state set to :prepared" do
            {:noreply, %{playback: new_playback}} =
              described_module().handle_info(message(), state())

            expect(new_playback.state) |> to(eq :prepared)
          end
        end
      end

      context "and current playback state is :prepared" do
        let :playback, do: %Playback{state: :prepared}

        before do
          allow(module()).to(
            accept(:handle_play, fn received_internal_state -> {:ok, received_internal_state} end)
          )

          allow(module()).to(
            accept(:handle_prepare, fn _previous_playback_state, received_internal_state ->
              {:ok, received_internal_state}
            end)
          )

          allow(module()).to(
            accept(:handle_stop, fn received_internal_state -> {:ok, received_internal_state} end)
          )
        end

        it "should not call handle_stop callback on element's module" do
          described_module().handle_info(message(), state())
          expect(module()) |> to_not(accepted(:handle_stop))
        end

        it "should not call handle_prepare callback on element's module" do
          described_module().handle_info(message(), state())
          expect(module()) |> to_not(accepted(:handle_prepare))
        end

        it "should not call handle_play callback on element's module" do
          described_module().handle_info(message(), state())
          expect(module()) |> to_not(accepted(:handle_play))
        end

        pending "should return {:reply, :noop, state()} with unmodified state"
      end

      context "and current playback state is :playing" do
        let :playback, do: %Playback{state: :playing}

        pending "and at least one of the callbacks has returned an error"

        context "and all callbacks have returned {:ok, state()}" do
          let :new_internal_state, do: :new_satete

          before do
            allow(module()).to(
              accept(:handle_play, fn received_internal_state ->
                {:ok, received_internal_state}
              end)
            )

            allow(module()).to(
              accept(:handle_prepare, fn _previous_playback_state, _state ->
                {:ok, new_internal_state()}
              end)
            )

            allow(module()).to(
              accept(:handle_stop, fn received_internal_state ->
                {:ok, received_internal_state}
              end)
            )
          end

          it "should not call handle_stop callback on element's module" do
            described_module().handle_info(message(), state())
            expect(module()) |> to_not(accepted(:handle_stop))
          end

          it "should call handle_prepare(:playing, internal_state) callback on element's module" do
            described_module().handle_info(message(), state())
            # , [:playing, internal_state()])
            expect(module()) |> to(accepted(:handle_prepare))
          end

          it "should not call handle_play callback on element's module" do
            described_module().handle_info(message(), state())
            expect(module()) |> to_not(accepted(:handle_play))
          end

          it "should return {:reply, :ok, state()} with internal state updated" do
            {:noreply, %{internal_state: returned_state}} =
              described_module().handle_info(message(), state())

            expect(returned_state) |> to(eq new_internal_state())
          end

          it "should return {:reply, :ok, state()} with playback state set to :prepared" do
            {:noreply, %{playback: returned_playback}} =
              described_module().handle_info(message(), state())

            expect(returned_playback.state) |> to(eq :prepared)
          end
        end
      end
    end

    context "if message is :membrane_stop" do
      let :message, do: {:membrane_change_playback_state, :stopped}
      let :module, do: TrivialFilter
      let :internal_state, do: %{}

      let :state,
        do: %State{module: module(), playback: playback(), internal_state: internal_state()}

      context "and current playback state is :playing" do
        let :playback, do: %Playback{state: :playing}

        pending "and at least one of the callbacks has returned an error"

        context "and all callbacks have returned {:ok, state()}" do
          let :new_internal_state, do: %{value: :new_value}

          before do
            allow(module()).to(
              accept(:handle_play, fn received_internal_state ->
                {:ok, received_internal_state}
              end)
            )

            allow(module()).to(
              accept(:handle_prepare, fn _previous_playback_state, received_internal_state ->
                {:ok, received_internal_state}
              end)
            )

            allow(module()).to(accept(:handle_stop, fn _ -> {:ok, new_internal_state()} end))
          end

          it "should call handle_stop callback on element's module" do
            described_module().handle_info(message(), state())
            expect(module()) |> to(accepted(:handle_stop, [internal_state()]))
          end

          it "should call handle_prepare(:playing, internal_state) callback on element's module" do
            described_module().handle_info(message(), state())
            expect(module()) |> to(accepted(:handle_prepare, [:playing, internal_state()]))
          end

          it "should not call handle_play callback on element's module" do
            described_module().handle_info(message(), state())
            expect(module()) |> to_not(accepted(:handle_play))
          end

          it "should return {:reply, :ok, state()} with internal state updated by handle_stop" do
            {:noreply, %{internal_state: returned_state}} =
              described_module().handle_info(message(), state())

            expect(returned_state) |> to(eq new_internal_state())
          end

          it "should return {:reply, :ok, state()} with playback state set to :stopped" do
            {:noreply, %{playback: returned_playback}} =
              described_module().handle_info(message(), state())

            expect(returned_playback.state) |> to(eq :stopped)
          end
        end
      end

      context "and current playback state is :prepared" do
        let :playback, do: %Playback{state: :prepared}

        pending "and at least one of the callbacks has returned an error"

        context "and all callbacks have returned {:ok, state()}" do
          let :new_internal_state, do: %{new: :new}

          before do
            allow(module()).to(
              accept(:handle_play, fn received_internal_state ->
                {:ok, received_internal_state}
              end)
            )

            allow(module()).to(
              accept(:handle_prepare, fn _previous_playback_state, received_internal_state ->
                {:ok, received_internal_state}
              end)
            )

            allow(module()).to(accept(:handle_stop, fn _state -> {:ok, new_internal_state()} end))
          end

          it "should call handle_stop callback on element's module" do
            described_module().handle_info(message(), state())
            expect(module()) |> to(accepted(:handle_stop, [internal_state()]))
          end

          it "should not call handle_prepare callback on element's module" do
            described_module().handle_info(message(), state())
            expect(module()) |> to_not(accepted(:handle_prepare))
          end

          it "should not call handle_play callback on element's module" do
            described_module().handle_info(message(), state())
            expect(module()) |> to_not(accepted(:handle_play))
          end

          it "should return {:reply, :ok, state()} with internal state updated" do
            {:noreply, %{internal_state: returned_state}} =
              described_module().handle_info(message(), state())

            expect(returned_state) |> to(eq new_internal_state())
          end

          it "should return {:reply, :ok, state()} with playback state set to :stopped" do
            {:noreply, %{playback: returned_playback}} =
              described_module().handle_info(message(), state())

            expect(returned_playback.state) |> to(eq :stopped)
          end
        end
      end

      context "and current playback state is :stopped" do
        let :playback, do: %Playback{state: :stopped}

        before do
          allow(module()).to(
            accept(:handle_play, fn received_internal_state -> {:ok, received_internal_state} end)
          )

          allow(module()).to(
            accept(:handle_prepare, fn _previous_playback_state, received_internal_state ->
              {:ok, received_internal_state}
            end)
          )

          allow(module()).to(
            accept(:handle_stop, fn received_internal_state -> {:ok, received_internal_state} end)
          )
        end

        it "should not call handle_stop callback on element's module" do
          described_module().handle_info(message(), state())
          expect(module()) |> to_not(accepted(:handle_stop))
        end

        it "should not call handle_prepare callback on element's module" do
          described_module().handle_info(message(), state())
          expect(module()) |> to_not(accepted(:handle_prepare))
        end

        it "should not call handle_play callback on element's module" do
          described_module().handle_info(message(), state())
          expect(module()) |> to_not(accepted(:handle_play))
        end

        it "should return {:reply, state()} with unmodified playback state" do
          {:noreply, %{playback: returned_playback}} =
            described_module().handle_info(message(), state())

          expect(returned_playback.state) |> to(eq :stopped)
        end
      end
    end
  end

  describe "handle_info/3" do
    context "if message is {:membrane_set_message_bus, pid}" do
      let :new_message_bus, do: self()
      let :message, do: {:membrane_set_message_bus, new_message_bus()}
      let :state, do: %State{module: TrivialFilter, message_bus: message_bus()}

      context "and current message bus is nil" do
        let :message_bus, do: nil

        it "should return {:noreply, :state()} with message bus set to the new message bus" do
          expect(described_module().handle_call(message(), self(), state()))
          |> to(eq {:reply, :ok, %{state() | message_bus: new_message_bus()}})
        end
      end

      context "and current message bus is set to the same message bus as requested" do
        let :message_bus, do: new_message_bus()

        it "should return {:reply, :ok, state()} with message bus set to the new message bus" do
          expect(described_module().handle_call(message(), self(), state()))
          |> to(eq {:reply, :ok, %{state() | message_bus: new_message_bus()}})
        end
      end
    end

    xcontext "if message is :membrane_get_message_bus" do
      let :message, do: :membrane_get_message_bus
      let :state, do: %State{module: TrivialFilter, message_bus: message_bus()}

      context "and current message bus is nil" do
        let :message_bus, do: nil

        it "should return {:reply, {:ok, nil}, state()} with unmodified state" do
          expect(described_module().handle_info(message(), state()))
          |> to(eq {:reply, {:ok, nil}, state()})
        end
      end

      context "and current message bus is not nil" do
        let :message_bus, do: self()

        it "should return {:reply, {:ok, pid}, state()} with unmodified state" do
          expect(described_module().handle_info(message(), state()))
          |> to(eq {:reply, {:ok, message_bus()}, state()})
        end
      end
    end

    xcontext "if message is :membrane_clear_message_bus" do
      let :message, do: :membrane_clear_message_bus
      let :state, do: %State{module: TrivialFilter, message_bus: message_bus()}

      context "and current message bus is nil" do
        let :message_bus, do: nil

        it "should return {:reply, :ok, state()} with message bus set to nil" do
          expect(described_module().handle_info(message(), state()))
          |> to(eq {:reply, :ok, %{state() | message_bus: nil}})
        end
      end

      context "and current message bus is not nil" do
        let :message_bus, do: self()

        it "should return {:reply, :ok, state()} with message bus set to nil" do
          expect(described_module().handle_info(message(), state()))
          |> to(eq {:reply, :ok, %{state() | message_bus: nil}})
        end
      end
    end
  end
end
