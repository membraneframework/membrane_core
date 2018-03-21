defmodule Membrane.Element.Manager.ActionExecSpec do
  use ESpec, async: false
  alias Membrane.Element.Manager.State
  alias Membrane.{Buffer, Event, Message}
  alias Membrane.Mixins.Playback

  pending ".handle_demand/6"
  pending ".handle_redemand/2"

  describe ".send_buffer/4" do
    let :other_name, do: :other_name
    let! :state, do: %{playback: playback(), name: :elem_name, __struct__: State, pads: %{data: %{source: %{direction: :source, pid: self(), other_name: other_name(), options: [], eos: false, mode: :push}}}}
    let :pad_name, do: :source
    let :payload, do: <<1,2,3,4,5>>
    let :buffer, do: %Buffer{payload: payload()}

    context "when element is not in a 'playing' state" do
      let :playback, do: %Playback{state: :prepared}

      context "and callback is not 'handle_play'" do
        let :callback, do: :handle_stop

        it "should return an error result" do
          {ret, _state} = described_module().send_buffer(pad_name(), buffer(), callback(), state())
          expect(ret).to be_error_result()
        end

        it "should return {:cannot_send_buffer, _} as a reason" do
          {{_error, {main_reason, _reason_details}}, _state} = described_module().send_buffer(pad_name(), buffer(), callback(), state())
          expect(main_reason).to eq(:cannot_send_buffer)
        end

        it "should return keyword list with callback name" do
          {{_error, {_main_reason, reason_details}}, _state} = described_module().send_buffer(pad_name(), buffer(), callback(), state())
          expect(reason_details |> Keyword.fetch(:callback)).to eq({:ok, callback()})
        end

        it "should return keyword list with playback state" do
          {{_error, {_main_reason, reason_details}}, _state} = described_module().send_buffer(pad_name(), buffer(), callback(), state())
          expect(reason_details |> Keyword.fetch(:playback_state)).to eq({:ok, playback().state})
        end
      end

      context "and callback is 'handle_play'" do
        let :callback, do: :handle_play


        context "but pad doesn't exist in the element" do
          let :invalid_pad_name, do: :invalid_pad_name

          it "should raise RuntimeError" do
            expect(fn -> described_module().send_buffer(invalid_pad_name(), buffer(), callback(), state()) end).to raise_exception(RuntimeError)
          end
        end

        context "and pad exists in element" do
          it "should return an ok result" do
            expect(described_module().send_buffer(pad_name(), buffer(), callback(), state())).to be_ok_result()
          end

          it "should keep element's state unchanged" do
            {:ok, new_state} = described_module().send_buffer(pad_name(), buffer(), callback(), state())
            expect(new_state).to eq(state())
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
            expect(fn -> described_module().send_buffer(invalid_pad_name(), buffer(), callback(), state()) end).to raise_exception(RuntimeError)
          end
        end

      context "and pad exists in element" do
        it "should return an ok result" do
          expect(described_module().send_buffer(pad_name(), buffer(), callback(), state())).to be_ok_result()
        end

        it "should keep element's state unchanged" do
          {:ok, new_state} = described_module().send_buffer(pad_name(), buffer(), callback(), state())
          expect(new_state).to eq(state())
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
    let! :state, do: %{playback: playback(), name: :elem_name, __struct__: State, pads: %{data: %{source: %{direction: :source, pid: self(), other_name: other_name(), options: [], eos: false, mode: :push}}}}
    let :pad_name, do: :source
    let :payload, do: <<1,2,3,4,5>>
    let :event, do: %Event{payload: payload()}

    context "when element is in a 'playing' state" do
      let :playback, do: %Playback{state: :playing}

      context "but pad doesn't exist in the element" do
          let :invalid_pad_name, do: :invalid_pad_name

          it "should raise RuntimeError" do
            expect(fn -> described_module().send_event(invalid_pad_name(), event(), state()) end).to raise_exception(RuntimeError)
          end
        end

      context "and pad exists in element" do
        it "should return an ok result" do
          expect(described_module().send_event(pad_name(), event(), state())).to be_ok_result()
        end

        it "should keep element's state unchanged" do
          {:ok, new_state} = described_module().send_event(pad_name(), event(), state())
          expect(new_state).to eq(state())
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
    let! :state, do: %{playback: playback(), name: :elem_name, __struct__: State, pads: %{data: %{source: %{direction: :source, pid: self(), other_name: other_name(), caps: nil, options: [], eos: false, mode: :push}}}}
    let :pad_name, do: :source
    let :payload, do: <<1,2,3,4,5>>
    let :caps, do: :caps

    context "when element is in a 'playing' state" do
      let :playback, do: %Playback{state: :playing}

      context "but pad doesn't exist in the element" do
          let :invalid_pad_name, do: :invalid_pad_name

          it "should raise RuntimeError" do
            expect(fn -> described_module().send_caps(invalid_pad_name(), caps(), state()) end).to raise_exception(RuntimeError)
          end
        end

      context "and pad exists in element" do
        it "should return an ok result" do
          expect(described_module().send_caps(pad_name(), caps(), state())).to be_ok_result()
        end

        it "should should return new state with updated caps" do
          updated_source = %{state().pads.data.source | caps: caps()}
          updated_data = %{state().pads.data | source: updated_source}
          expected_pads = %{state().pads | data: updated_data}
          expected_state = %{state() | pads: expected_pads}

          {:ok, new_state} = described_module().send_caps(pad_name(), caps(), state())
          expect(new_state).to eq(expected_state)
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
        expect(described_module().send_message(message(), state())).to be_ok_result()
      end

      it "should keep element's state unchanged" do
        expect(described_module().send_message(message(), state()) |> elem(1)).to eq(state())
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
        expect(described_module().send_message(message(), state())).to be_ok_result()
      end

      it "should keep element's state unchanged" do
        expect(described_module().send_message(message(), state()) |> elem(1)).to eq(state())
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
end
