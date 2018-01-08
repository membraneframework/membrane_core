defmodule Membrane.Element.Manager.ActionSpec do
  use ESpec, async: false
  alias Membrane.Element.Manager.State
  alias Membrane.{Buffer, Caps, Event, Message, Pad}
  alias Membrane.Support.Element.TrivialFilter

  describe ".send_buffer/4" do
    let :other_name, do: :other_name
    let! :state, do: %{playback_state: playback_state(), name: :elem_name, __struct__: State, pads: %{data: %{source: %{direction: :source, pid: self(), other_name: other_name(), options: [], eos: false, mode: :push}}}}
    let :pad_name, do: :source
    let :payload, do: <<1,2,3,4,5>>
    let :buffer, do: %Buffer{payload: payload()}

    context "when element is not in a 'playing' state" do
      let :playback_state, do: :prepared
      
      context "and callback is not 'handle_play'" do
        let :callback, do: :handle_stop

        it "should return an error result" do
          ret = described_module().send_buffer(pad_name(), buffer(), callback(), state())
          expect(ret).to be_error_result()
        end

        it "should return {:cannot_send_buffer, _} as a reason" do
          {_, {atom, _}} = described_module().send_buffer(pad_name(), buffer(), callback(), state())
          expect(atom).to eq(:cannot_send_buffer) 
        end

        it "should return keyword list with callback name" do
          {_, {_, keyword}} = described_module().send_buffer(pad_name(), buffer(), callback(), state())
          expect(keyword |> Keyword.fetch(:callback)).to eq({:ok, callback()})
        end

        it "should return keyword list with plaback state" do
          {_, {_, keyword}} = described_module().send_buffer(pad_name(), buffer(), callback(), state())
          expect(keyword |> Keyword.fetch(:playback_state)).to eq({:ok, playback_state()})
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
      let :playback_state, do: :playing
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
end
