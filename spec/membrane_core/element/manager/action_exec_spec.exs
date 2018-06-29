defmodule Membrane.Element.Manager.ActionExecSpec do
  use ESpec, async: false
  alias Membrane.Element.Manager.State
  alias Membrane.{Buffer, Event, Message}
  alias Membrane.Mixins.Playback

  describe ".send_buffer/4" do
    let :other_name, do: :other_name

    let! :state,
      do: %{
        playback: playback(),
        name: :elem_name,
        __struct__: State,
        pads: %{
          data: %{
            source: %{
              direction: :source,
              pid: self(),
              other_name: other_name(),
              options: [],
              eos: false,
              mode: :push
            }
          }
        }
      }

    let :pad_name, do: :source
    let :payload, do: <<1, 2, 3, 4, 5>>
    let :buffer, do: %Buffer{payload: payload()}

    context "when element is not in a 'playing' state" do
      let :playback, do: %Playback{state: :prepared}

      context "and callback is not 'handle_play'" do
        let :callback, do: :handle_stop

        it "should return an error result" do
          {ret, _state} =
            described_module().send_buffer(pad_name(), buffer(), callback(), state())

          expect(ret) |> to(be_error_result())
        end

        it "should return {:cannot_send_buffer, _} as a reason" do
          {{_error, {main_reason, _reason_details}}, _state} =
            described_module().send_buffer(pad_name(), buffer(), callback(), state())

          expect(main_reason) |> to(eq :cannot_send_buffer)
        end

        it "should return keyword list with callback name" do
          {{_error, {_main_reason, reason_details}}, _state} =
            described_module().send_buffer(pad_name(), buffer(), callback(), state())

          expect(reason_details |> Keyword.fetch(:callback)) |> to(eq {:ok, callback()})
        end

        it "should return keyword list with playback state" do
          {{_error, {_main_reason, reason_details}}, _state} =
            described_module().send_buffer(pad_name(), buffer(), callback(), state())

          expect(reason_details |> Keyword.fetch(:playback_state))
          |> to(eq {:ok, playback().state})
        end
      end

      context "and callback is 'handle_play'" do
        let :callback, do: :handle_play

        context "but pad doesn't exist in the element" do
          let :invalid_pad_name, do: :invalid_pad_name

          it "should raise RuntimeError" do
            expect(fn ->
              described_module().send_buffer(invalid_pad_name(), buffer(), callback(), state())
            end).to(raise_exception RuntimeError)
          end
        end

        context "and pad exists in element" do
          it "should return an ok result" do
            expect(described_module().send_buffer(pad_name(), buffer(), callback(), state()))
            |> to(be_ok_result())
          end

          it "should keep element's state unchanged" do
            {:ok, new_state} =
              described_module().send_buffer(pad_name(), buffer(), callback(), state())

            expect(new_state) |> to(eq state())
          end

          it "should send {:membrane_buffer, _} message to pid()" do
            described_module().send_buffer(pad_name(), buffer(), callback(), state())
            target = {:membrane_buffer, [[buffer()], other_name()]}
            assert_receive ^target
          end
        end
      end
    end

    context "when element is in a 'playing' state" do
      let :playback, do: %Playback{state: :playing}
      let :callback, do: :any

      context "but pad doesn't exist in the element" do
        let :invalid_pad_name, do: :invalid_pad_name

        it "should raise RuntimeError" do
          expect(fn ->
            described_module().send_buffer(invalid_pad_name(), buffer(), callback(), state())
          end).to(raise_exception RuntimeError)
        end
      end

      context "and pad exists in element" do
        it "should return an ok result" do
          expect(described_module().send_buffer(pad_name(), buffer(), callback(), state()))
          |> to(be_ok_result())
        end

        it "should keep element's state unchanged" do
          {:ok, new_state} =
            described_module().send_buffer(pad_name(), buffer(), callback(), state())

          expect(new_state) |> to(eq state())
        end

        it "should send {:membrane_buffer, _} message to pid()" do
          described_module().send_buffer(pad_name(), buffer(), callback(), state())
          target = {:membrane_buffer, [[buffer()], other_name()]}
          assert_receive ^target
        end
      end
    end
  end

  describe ".send_event/3" do
    let :other_name, do: :other_name

    let! :state,
      do: %{
        playback: playback(),
        name: :elem_name,
        __struct__: State,
        pads: %{
          data: %{
            source: %{
              direction: :source,
              pid: self(),
              other_name: other_name(),
              options: [],
              eos: false,
              mode: :push
            }
          }
        }
      }

    let :pad_name, do: :source
    let :payload, do: <<1, 2, 3, 4, 5>>
    let :event, do: %Event{payload: payload()}

    context "when element is in a 'playing' state" do
      let :playback, do: %Playback{state: :playing}

      context "but pad doesn't exist in the element" do
        let :invalid_pad_name, do: :invalid_pad_name

        it "should raise RuntimeError" do
          expect(fn -> described_module().send_event(invalid_pad_name(), event(), state()) end)
          |> to(raise_exception RuntimeError)
        end
      end

      context "and pad exists in element" do
        it "should return an ok result" do
          expect(described_module().send_event(pad_name(), event(), state()))
          |> to(be_ok_result())
        end

        it "should keep element's state unchanged" do
          {:ok, new_state} = described_module().send_event(pad_name(), event(), state())
          expect(new_state) |> to(eq state())
        end

        context "and event is special" do
          let :payload, do: "special payload"

          it "should send {:membrane_event, _} message to self()" do
            described_module().send_event(pad_name(), event(), state())
            target = {:membrane_event, [event(), other_name()]}
            assert_receive ^target
          end
        end
      end
    end
  end

  describe ".send_caps/3" do
    let :other_name, do: :other_name

    let! :state,
      do: %{
        playback: playback(),
        name: :elem_name,
        __struct__: State,
        pads: %{
          data: %{
            source: %{
              direction: :source,
              pid: self(),
              other_name: other_name(),
              caps: nil,
              options: [],
              eos: false,
              mode: :push,
              accepted_caps: :any
            }
          }
        }
      }

    let :pad_name, do: :source
    let :payload, do: <<1, 2, 3, 4, 5>>
    let :caps, do: :caps

    context "when element is in a 'playing' state" do
      let :playback, do: %Playback{state: :playing}

      context "but pad doesn't exist in the element" do
        let :invalid_pad_name, do: :invalid_pad_name

        it "should raise RuntimeError" do
          expect(fn -> described_module().send_caps(invalid_pad_name(), caps(), state()) end)
          |> to(raise_exception RuntimeError)
        end
      end

      context "and pad exists in element" do
        it "should return an ok result" do
          expect(described_module().send_caps(pad_name(), caps(), state())) |> to(be_ok_result())
        end

        it "should should return new state with updated caps" do
          updated_source = %{state().pads.data.source | caps: caps()}
          updated_data = %{state().pads.data | source: updated_source}
          expected_pads = %{state().pads | data: updated_data}
          expected_state = %{state() | pads: expected_pads}

          {:ok, new_state} = described_module().send_caps(pad_name(), caps(), state())
          expect(new_state) |> to(eq expected_state)
        end

        context "and event is special" do
          let :payload, do: "special payload"

          it "should send {:membrane_event, _} message to self()" do
            described_module().send_caps(pad_name(), caps(), state())
            target = {:membrane_caps, [caps(), other_name()]}
            assert_receive ^target
          end
        end
      end
    end
  end

  describe ".send_message/2" do
    let :name, do: :some_name
    let :state, do: %State{message_bus: message_bus(), name: name()}
    let :payload, do: "some message"
    let :message, do: %Message{payload: payload()}

    context "when message_bus is nil" do
      let :message_bus, do: nil

      it "should return an ok result" do
        expect(described_module().send_message(message(), state())) |> to(be_ok_result())
      end

      it "should keep element's state unchanged" do
        expect(described_module().send_message(message(), state()) |> elem(1)) |> to(eq state())
      end

      context "and message is special" do
        let :payload, do: "some special payload 1"

        it "should not receive :membrane_message" do
          described_module().send_message(message(), state())
          target = [:membrane_message, name(), message()]
          refute_receive ^target
        end
      end
    end

    context "when message_bus is not nil" do
      let :message_bus, do: self()

      it "should return an ok result" do
        expect(described_module().send_message(message(), state())) |> to(be_ok_result())
      end

      it "should keep element's state unchanged" do
        expect(described_module().send_message(message(), state()) |> elem(1)) |> to(eq state())
      end

      context "and message is special" do
        let :payload, do: "some special payload 2"

        it "should receive {:membrane_message, _}" do
          described_module().send_message(message(), state())
          target = [:membrane_message, name(), message()]
          assert_receive ^target
        end
      end
    end
  end

  describe ".handle_demand" do
    let :callback, do: :handle_event
    let :source, do: :self
    let :pad_name, do: :sink
    let :size, do: 1
    let :type, do: :normal
    let :sink_mode, do: :pull
    let :playback_state, do: :playing
    let :element_module, do: FakeElementModule
    let :manager_module, do: FakeManagerModule

    let :state,
      do: %{
        __struct__: State,
        module: element_module(),
        name: :test_name,
        playback_state: playback_state(),
        pads: %{
          data: %{
            sink: %{
              direction: :sink,
              mode: sink_mode(),
              pid: self()
            }
          }
        }
      }

    context "when sink pad is not in a pull mode" do
      let :sink_mode, do: :push

      it "should raise RuntimeError" do
        expect(fn ->
          described_module().handle_demand(
            pad_name(),
            source(),
            type(),
            size(),
            callback(),
            state()
          )
        end)
        |> to(raise_exception(RuntimeError))
      end
    end

    context "when source doesn't exist in the given state" do
      let :source, do: {:source, :non_existing_pad}

      it "should raise RuntimeError" do
        expect(fn ->
          described_module().handle_demand(
            pad_name(),
            source(),
            type(),
            size(),
            callback(),
            state()
          )
        end)
        |> to(raise_exception(RuntimeError))
      end
    end

    context "when callback is 'handle_write'" do
      let :callback, do: :handle_write

      it "should send appropriate message to 'self()'" do
        described_module().handle_demand(
          pad_name(),
          source(),
          type(),
          size(),
          callback(),
          state()
        )

        assert_received {:membrane_self_demand, _}
      end
    end

    context "when callback is other than 'handle_write' or 'handle_process'" do
      before do: allow(element_module() |> to(accept :manager_module, fn -> manager_module() end))

      before do:
               allow(
                 manager_module()
                 |> to(accept :handle_self_demand, fn _, _, _, _, _ -> :ok end)
               )

      it "should call handle_self_demand method of the given manager" do
        described_module().handle_demand(
          pad_name(),
          source(),
          type(),
          size(),
          callback(),
          state()
        )

        expect(element_module() |> to(accepted(:manager_module, :any, count: 1)))
      end
    end
  end

  describe ".handle_redemand" do
    let :pad_name, do: :source
    let :pad_direction, do: :source
    let :pad_mode, do: :pull
    let :element_module, do: FakeElementModule
    let :manager_module, do: FakeManagerModule

    let :state,
      do: %{
        __struct__: State,
        module: element_module(),
        pads: %{
          data: %{
            source: %{
              direction: pad_direction(),
              pid: self(),
              mode: pad_mode()
            }
          }
        }
      }

    context "if pad doesn't exist in the element" do
      it "should return an error result with :unknown_pad reason" do
        expect(fn -> described_module().handle_redemand(:invalid_pad_name, state()) end)
        |> to(raise_exception(RuntimeError))
      end
    end

    context "if pad works in a push mode" do
      let :pad_mode, do: :push

      it "should raise RuntimeError" do
        expect(fn -> described_module().handle_redemand(pad_name(), state()) end)
        |> to(raise_exception(RuntimeError))
      end
    end

    context "if given pad works in a pull mode" do
      let :pad_mode, do: :pull

      before do: allow(element_module() |> to(accept :manager_module, fn -> manager_module() end))

      before do:
               allow(
                 manager_module()
                 |> to(accept :handle_redemand, fn _, _ -> :ok end)
               )

      it "should call handle_redemand method of the given module" do
        described_module().handle_redemand(pad_name(), state())
        expect(manager_module() |> to(accepted(:handle_redemand, :any, count: 1)))
      end
    end
  end
end
