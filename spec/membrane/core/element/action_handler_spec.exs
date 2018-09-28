defmodule Membrane.Core.Element.ActionHandlerSpec do
  use ESpec, async: false
  alias Membrane.Support.TestingEvent
  alias Membrane.Core.Element.State
  alias Membrane.{Buffer, Message}
  alias Membrane.Core.{Playback, Element}

  describe "handle_action for buffer" do
    let :other_ref, do: :other_ref

    let! :state,
      do: %{
        playback: playback(),
        type: :filter,
        name: :elem_name,
        __struct__: State,
        pads: %{
          data: %{
            output: %{
              direction: :output,
              pid: self(),
              other_ref: other_ref(),
              other_demand_unit: :bytes,
              end_of_stream: false,
              mode: :push
            }
          }
        }
      }

    let :pad_ref, do: :output
    let :payload, do: <<1, 2, 3, 4, 5>>
    let :buffer, do: %Buffer{payload: payload()}

    context "when element is not in a 'playing' state" do
      let :playback, do: %Playback{state: :prepared}

      context "and callback is not 'handle_prepared_to_playing'" do
        let :callback, do: :handle_prepared_to_stopped

        it "should return an error result" do
          {ret, _state} =
            described_module().handle_action(
              {:buffer, {pad_ref(), buffer()}},
              callback(),
              %{},
              state()
            )

          expect(ret) |> to(be_error_result())
        end

        it "should return {:cannot_send_buffer, _} as a reason" do
          {{_error, {main_reason, _reason_details}}, _state} =
            described_module().handle_action(
              {:buffer, {pad_ref(), buffer()}},
              callback(),
              %{},
              state()
            )

          expect(main_reason) |> to(eq :cannot_handle_action)
        end

        it "should return keyword list with callback name" do
          {{_error, {_main_reason, reason_details}}, _state} =
            described_module().handle_action(
              {:buffer, {pad_ref(), buffer()}},
              callback(),
              %{},
              state()
            )

          expect(reason_details |> Keyword.fetch(:callback)) |> to(eq {:ok, callback()})
        end

        it "should return keyword list with playback state" do
          {{:error, {_main_reason, reason_details}}, _state} =
            described_module().handle_action(
              {:buffer, {pad_ref(), buffer()}},
              callback(),
              %{},
              state()
            )

          {:ok, {_main_reason, reason_details}} = reason_details |> Keyword.fetch(:reason)

          expect(reason_details |> Keyword.fetch(:playback_state))
          |> to(eq {:ok, playback().state})
        end
      end

      context "and callback is 'handle_prepared_to_playing'" do
        let :callback, do: :handle_prepared_to_playing

        context "and pad exists in element" do
          it "should return an ok result" do
            expect(
              described_module().handle_action(
                {:buffer, {pad_ref(), buffer()}},
                callback(),
                %{},
                state()
              )
            )
            |> to(be_ok_result())
          end

          it "should keep element's state unchanged" do
            {:ok, new_state} =
              described_module().handle_action(
                {:buffer, {pad_ref(), buffer()}},
                callback(),
                %{},
                state()
              )

            expect(new_state) |> to(eq state())
          end

          it "should send {:membrane_buffer, _} message to pid()" do
            described_module().handle_action(
              {:buffer, {pad_ref(), buffer()}},
              callback(),
              %{},
              state()
            )

            target = {:membrane_buffer, [[buffer()], other_ref()]}
            assert_receive ^target
          end
        end
      end
    end

    context "when element is in a 'playing' state" do
      let :playback, do: %Playback{state: :playing}
      let :callback, do: :any

      context "but pad doesn't exist in the element" do
        let :invalid_pad_ref, do: :invalid_pad_ref

        it "should return error" do
          {{:error, {main_reason, reason_details}}, state} =
            described_module().handle_action(
              {:buffer, {invalid_pad_ref(), buffer()}},
              callback(),
              %{},
              state()
            )

          expect(main_reason) |> to(eq :cannot_handle_action)

          expect(reason_details |> Keyword.get(:reason))
          |> to(eq {:unknown_pad, :invalid_pad_ref})

          expect(state) |> to(eq state())
        end
      end

      context "and pad exists in element" do
        it "should return an ok result" do
          expect(
            described_module().handle_action(
              {:buffer, {pad_ref(), buffer()}},
              callback(),
              %{},
              state()
            )
          )
          |> to(be_ok_result())
        end

        it "should keep element's state unchanged" do
          {:ok, new_state} =
            described_module().handle_action(
              {:buffer, {pad_ref(), buffer()}},
              callback(),
              %{},
              state()
            )

          expect(new_state) |> to(eq state())
        end

        it "should send {:membrane_buffer, _} message to pid()" do
          described_module().handle_action(
            {:buffer, {pad_ref(), buffer()}},
            callback(),
            %{},
            state()
          )

          target = {:membrane_buffer, [[buffer()], other_ref()]}
          assert_receive ^target
        end
      end
    end
  end

  describe "handle_action for event" do
    let :other_ref, do: :other_ref

    let! :state,
      do: %{
        playback: playback(),
        name: :elem_name,
        type: :filter,
        __struct__: State,
        pads: %{
          data: %{
            output: %{
              direction: :output,
              pid: self(),
              other_ref: other_ref(),
              other_demand_unit: :bytes,
              end_of_stream: false,
              mode: :push
            }
          }
        }
      }

    let :pad_ref, do: :output
    let :payload, do: <<1, 2, 3, 4, 5>>
    let :event, do: %TestingEvent{}

    context "when element is in a 'playing' state" do
      let :playback, do: %Playback{state: :playing}

      context "but pad doesn't exist in the element" do
        let :invalid_pad_ref, do: :invalid_pad_ref

        it "should return error" do
          {{:error, {main_reason, reason_details}}, state} =
            described_module().handle_action(
              {:caps, {invalid_pad_ref(), event()}},
              nil,
              %{},
              state()
            )

          expect(main_reason) |> to(eq :cannot_handle_action)

          expect(reason_details |> Keyword.get(:reason))
          |> to(eq {:unknown_pad, :invalid_pad_ref})

          expect(state) |> to(eq state())
        end
      end

      context "and pad exists in element" do
        it "should return an ok result" do
          expect(
            described_module().handle_action({:event, {pad_ref(), event()}}, nil, %{}, state())
          )
          |> to(be_ok_result())
        end

        it "should keep element's state unchanged" do
          {:ok, new_state} =
            described_module().handle_action({:event, {pad_ref(), event()}}, nil, %{}, state())

          expect(new_state) |> to(eq state())
        end

        context "and event is special" do
          let :payload, do: "special payload"

          it "should send {:membrane_event, _} message to self()" do
            described_module().handle_action({:event, {pad_ref(), event()}}, nil, %{}, state())
            target = {:membrane_event, [event(), other_ref()]}
            assert_receive ^target
          end
        end
      end
    end
  end

  describe "handle_action for caps" do
    let :other_ref, do: :other_ref

    let! :state,
      do: %{
        playback: playback(),
        name: :elem_name,
        type: :filter,
        __struct__: State,
        pads: %{
          data: %{
            output: %{
              direction: :output,
              pid: self(),
              other_ref: other_ref(),
              caps: nil,
              other_demand_unit: :bytes,
              end_of_stream: false,
              mode: :push,
              accepted_caps: :any
            }
          }
        }
      }

    let :pad_ref, do: :output
    let :payload, do: <<1, 2, 3, 4, 5>>
    let :caps, do: :caps

    context "when element is in a 'playing' state" do
      let :playback, do: %Playback{state: :playing}

      context "but pad doesn't exist in the element" do
        let :invalid_pad_ref, do: :invalid_pad_ref

        it "should return error" do
          {{:error, {main_reason, reason_details}}, state} =
            described_module().handle_action(
              {:caps, {invalid_pad_ref(), caps()}},
              nil,
              %{},
              state()
            )

          expect(main_reason) |> to(eq :cannot_handle_action)

          expect(reason_details |> Keyword.get(:reason))
          |> to(eq {:unknown_pad, :invalid_pad_ref})

          expect(state) |> to(eq state())
        end
      end

      context "and pad exists in element" do
        it "should return an ok result" do
          expect(
            described_module().handle_action({:caps, {pad_ref(), caps()}}, nil, %{}, state())
          )
          |> to(be_ok_result())
        end

        it "should should return new state with updated caps" do
          updated_output = %{state().pads.data.output | caps: caps()}
          updated_data = %{state().pads.data | output: updated_output}
          expected_pads = %{state().pads | data: updated_data}
          expected_state = %{state() | pads: expected_pads}

          {:ok, new_state} =
            described_module().handle_action({:caps, {pad_ref(), caps()}}, nil, %{}, state())

          expect(new_state) |> to(eq expected_state)
        end

        context "and event is special" do
          let :payload, do: "special payload"

          it "should send {:membrane_event, _} message to self()" do
            described_module().handle_action({:caps, {pad_ref(), caps()}}, nil, %{}, state())
            target = {:membrane_caps, [caps(), other_ref()]}
            assert_receive ^target
          end
        end
      end
    end
  end

  describe "handle_action for message" do
    let :name, do: :some_name
    let :state, do: %State{message_bus: message_bus(), name: name()}
    let :payload, do: "some message"
    let :message, do: %Message{payload: payload()}

    context "when message_bus is nil" do
      let :message_bus, do: nil

      it "should return an ok result" do
        expect(described_module().handle_action({:message, message()}, nil, %{}, state()))
        |> to(be_ok_result())
      end

      it "should keep element's state unchanged" do
        expect(
          described_module().handle_action({:message, message()}, nil, %{}, state())
          |> elem(1)
        )
        |> to(eq state())
      end

      context "and message is special" do
        let :payload, do: "some special payload 1"

        it "should not receive :membrane_message" do
          described_module().handle_action({:message, message()}, nil, %{}, state())
          target = [:membrane_message, name(), message()]
          refute_receive ^target
        end
      end
    end

    context "when message_bus is not nil" do
      let :message_bus, do: self()

      it "should return an ok result" do
        expect(described_module().handle_action({:message, message()}, nil, %{}, state()))
        |> to(be_ok_result())
      end

      it "should keep element's state unchanged" do
        expect(
          described_module().handle_action({:message, message()}, nil, %{}, state())
          |> elem(1)
        )
        |> to(eq state())
      end

      context "and message is special" do
        let :payload, do: "some special payload 2"

        it "should receive {:membrane_message, _}" do
          described_module().handle_action({:message, message()}, nil, %{}, state())
          target = [:membrane_message, name(), message()]
          assert_receive ^target
        end
      end
    end
  end

  describe "handle_action for demand" do
    let :action, do: {:demand, {pad_ref(), size()}}
    let :callback, do: :handle_event
    let :pad_ref, do: :input
    let :size, do: 1
    let :type, do: :normal
    let :mode, do: :pull
    let :element_type, do: :filter
    let :playback_state, do: :playing
    let :element_module, do: FakeElementModule
    let :handler_module, do: Element.DemandHandler

    let :state,
      do: %{
        __struct__: State,
        module: element_module(),
        name: :test_name,
        type: element_type(),
        playback_state: playback_state(),
        pads: %{
          data: %{
            input: %{
              direction: :input,
              mode: mode(),
              pid: self()
            }
          }
        }
      }

    context "when input pad is not in a pull mode" do
      let :mode, do: :push

      it "should return an error with proper reason" do
        result = described_module().handle_action(action(), callback(), %{}, state())
        expect(result) |> to(match_pattern {{:error, {:cannot_handle_action, _}}, _})
        {{:error, {:cannot_handle_action, details}}, _} = result
        expect(details[:reason]) |> to(match_pattern {:invalid_pad_data, _})
      end
    end

    context "when callback is 'handle_write_list'" do
      let :callback, do: :handle_write_list

      it "should send appropriate message to 'self()'" do
        result =
          described_module().handle_action(
            action(),
            callback(),
            %{},
            state()
          )

        expect(result) |> to(be_ok_result())
        assert_received {:membrane_invoke_supply_demand, _}
      end
    end
  end

  describe "handle_action for redemand" do
    let :action, do: {:redemand, pad_ref()}

    let :pad_ref, do: :output
    let :pad_direction, do: :output
    let :pad_mode, do: :pull
    let :element_module, do: FakeElementModule
    let :controller_module, do: Element.DemandController

    let :state,
      do: %{
        __struct__: State,
        module: element_module(),
        name: :test_name,
        type: :source,
        pads: %{
          data: %{
            output: %{
              direction: pad_direction(),
              pid: self(),
              mode: pad_mode(),
              invoke_redemand: false
            }
          }
        }
      }

    context "if pad doesn't exist in the element" do
      let :pad_ref, do: :invalid_pad_ref

      it "should return an error result with :unknown_pad reason" do
        result = described_module().handle_action(action(), nil, %{}, state())
        expect(result) |> to(match_pattern {{:error, {:cannot_handle_action, _}}, _})
        {{:error, {:cannot_handle_action, details}}, _} = result
        expect(details[:reason]) |> to(eq {:unknown_pad, :invalid_pad_ref})
      end
    end

    context "if pad works in a push mode" do
      let :pad_mode, do: :push

      it "should return an error" do
        result = described_module().handle_action(action(), nil, %{}, state())
        expect(result) |> to(match_pattern {{:error, {:cannot_handle_action, _}}, _})
        {{:error, {:cannot_handle_action, details}}, _} = result
        expect(details[:reason]) |> to(match_pattern {:invalid_pad_data, _})
      end
    end

    context "if given pad works in a pull mode" do
      let :pad_mode, do: :pull

      it "should set invoke_redemand in pad's data" do
        res = described_module().handle_action(action(), :handle_write_list, %{}, state())

        expected_state =
          Bunch.Struct.update_in(state(), [:pads, :data, :output, :invoke_redemand], fn _ ->
            true
          end)

        expect(res |> to(eq {:ok, expected_state}))
      end
    end
  end

  describe "handle_actions" do
    let :pad_ref, do: :output
    let :pad_direction, do: :output
    let :pad_mode, do: :pull
    let :element_module, do: FakeElementModule
    let :controller_module, do: Element.DemandController
    let :message_a, do: %Message{payload: :a}
    let :message_b, do: %Message{payload: :b}

    let :state,
      do: %{
        __struct__: State,
        message_bus: self(),
        module: element_module(),
        name: :test_name,
        type: :source,
        pads: %{
          data: %{
            output: %{
              direction: pad_direction(),
              pid: self(),
              mode: pad_mode(),
              invoke_redemand: false
            }
          }
        }
      }

    before do
      allow controller_module() |> to(accept :handle_demand, fn _, 0, state -> {:ok, state} end)
    end

    context "if :redemand is the last action" do
      let :actions, do: [message: message_a(), message: message_b(), redemand: :output]

      it "should handle all actions" do
        res = described_module().handle_actions(actions(), nil, %{}, state())
        expect(res |> to(eq {:ok, state()}))
        msg_a = [:membrane_message, :test_name, message_a()]
        msg_b = [:membrane_message, :test_name, message_b()]
        assert_received(^msg_a)
        assert_received(^msg_b)
        expect(controller_module() |> to(accepted(:handle_demand, :any, count: 1)))
      end
    end

    context "if :redemand is not the last action" do
      let :actions, do: [redemand: :output, message: message_a(), message: message_b()]

      it "should return an error" do
        res = described_module().handle_actions(actions(), nil, %{}, state())
        expect(res |> to(eq {{:error, :actions_after_redemand}, state()}))
        msg_a = [:membrane_message, :test_name, message_a()]
        msg_b = [:membrane_message, :test_name, message_b()]
        refute_received(^msg_a)
        refute_received(^msg_b)
        expect(controller_module() |> to(accepted(:handle_demand, :any, count: 0)))
      end
    end

    context "if actions don't contain :redemand" do
      let :actions, do: [message: message_a(), message: message_b()]

      it "should handle all actions" do
        res = described_module().handle_actions(actions(), nil, %{}, state())
        expect(res |> to(eq {:ok, state()}))
        msg_a = [:membrane_message, :test_name, message_a()]
        msg_b = [:membrane_message, :test_name, message_b()]
        assert_received(^msg_a)
        assert_received(^msg_b)
      end
    end
  end
end
