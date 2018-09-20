defmodule Membrane.ElementSpec do
  use ESpec, async: false

  alias Membrane.Support.Element.{TrivialFilter, TrivialSink, TrivialSource}
  alias Membrane.Element.CallbackContext
  alias Membrane.Core.{Message, Playback}
  alias Membrane.Core.Element.State
  require Message

  pending ".start_link/3"
  pending ".start/3"

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
      finally do: Process.exit(destination(), :kill)

      context "but first given PID is not a source" do
        let :server_module, do: TrivialSink
        let :destination_module, do: TrivialSink

        it "should return an error result" do
          expect(described_module().link(server(), destination(), :sink, :sink, []))
          |> to(be_error_result())
        end

        it "should return :invalid_pad_direction as a reason" do
          {:error, val} = described_module().link(server(), destination(), :sink, :sink, [])
          {:handle_call, {:cannot_handle_message, [message: _, mode: _, reason: reason]}} = val
          expect(reason) |> to(eq {:invalid_pad_direction, [expected: :source, actual: :sink]})
        end
      end

      context "but second given PID is not a sink" do
        let :server_module, do: TrivialSource
        let :destination_module, do: TrivialSource

        it "should return an error result" do
          expect(described_module().link(server(), destination(), :source, :source, []))
          |> to(be_error_result())
        end

        it "should return :invalid_pad_direction as a reason" do
          {_, val} = described_module().link(server(), destination(), :source, :source, [])

          {:handle_call, {:cannot_handle_message, keyword_list}} = val
          reason = keyword_list |> Keyword.get(:reason)
          expect(reason) |> to(eq {:invalid_pad_direction, [expected: :sink, actual: :source]})
        end
      end

      context "but incorrect pad ref is given" do
        let :server_module, do: TrivialSource
        let :destination_module, do: TrivialSink

        it "should return an error result" do
          expect(described_module().link(server(), destination(), :s, :s, []))
          |> to(be_error_result())
        end

        it "should return :unknown_pad as a reason" do
          {_, val} = described_module().link(server(), destination(), :s, :s, [])
          {:handle_call, {:cannot_handle_message, keyword_list}} = val
          expect(keyword_list |> Keyword.get(:reason)) |> to(eq :unknown_pad)
        end
      end

      context "and first given PID is a source and second given PID is a sink" do
        let :server_module, do: TrivialSource
        let :destination_module, do: TrivialSink

        context "but pads are already linked" do
          before do: :ok = described_module().link(server(), destination(), :source, :sink, [])

          it "should return an error result" do
            expect(described_module().link(server(), destination(), :source, :sink, []))
            |> to(be_error_result())
          end

          it "should return :already_linked as a reason" do
            {_, val} = described_module().link(server(), destination(), :source, :sink, [])
            {:handle_call, {:cannot_handle_message, keyword_list}} = val
            expect(keyword_list |> Keyword.get(:reason)) |> to(eq :already_linked)
          end
        end
      end
    end
  end

  describe ".handle_info/3" do
    context "change playback state to playing" do
      let :message, do: Message.new(:change_playback_state, :playing)
      let :module, do: TrivialSource
      let :internal_state, do: %{a: 1}
      let :ctx_playback_change, do: %CallbackContext.PlaybackChange{}

      let :state,
        do: %State{
          module: module(),
          playback: playback(),
          playback_buffer: Membrane.Core.Element.PlaybackBuffer.new(),
          internal_state: internal_state()
        }

      context "and current playback state is :stopped" do
        let :playback, do: %Playback{state: :stopped}

        context "and handle_stopped_to_prepared callback has returned an error" do
          let :reason, do: :whatever

          before do
            allow module()
                  |> to(
                    accept(:handle_prepared_to_playing, fn _ctx, received_internal_state ->
                      {:ok, received_internal_state}
                    end)
                  )

            allow module()
                  |> to(
                    accept(:handle_stopped_to_prepared, fn _ctx, received_internal_state ->
                      {{:error, reason()}, %{received_internal_state | a: 2}}
                    end)
                  )

            allow module()
                  |> to(
                    accept(:handle_prepared_to_stopped, fn _ctx, received_internal_state ->
                      {:ok, received_internal_state}
                    end)
                  )
          end

          it "should not call handle_prepared_to_stopped callback on element's module" do
            described_module().handle_info(message(), state())
            expect(module()) |> to_not(accepted(:handle_prepared_to_stopped))
          end

          it "should call handle_stopped_to_prepared(ctx, internal_state) callback on element's module" do
            described_module().handle_info(message(), state())

            expect(module())
            |> to(
              accepted(:handle_stopped_to_prepared, [ctx_playback_change(), internal_state()])
            )
          end

          it "should not call handle_prepared_to_playing(ctx, internal_state) callback on element's module" do
            described_module().handle_info(message(), state())
            expect(module()) |> to_not(accepted(:handle_prepared_to_playing))
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

        context "and handle_prepared_to_playing callback has returned an error" do
          let :reason, do: :whatever

          before do
            allow module()
                  |> to(
                    accept(:handle_prepared_to_playing, fn _, received_internal_state ->
                      {:error, reason(), %{received_internal_state | a: 3}}
                    end)
                  )

            allow module()
                  |> to(
                    accept(:handle_stopped_to_prepared, fn _ctx, internal_state ->
                      {:ok, %{internal_state | a: 2}}
                    end)
                  )

            allow module()
                  |> to(
                    accept(:handle_prepared_to_stopped, fn _, received_internal_state ->
                      {:ok, received_internal_state}
                    end)
                  )
          end

          it "should not call handle_prepared_to_stopped callback on element's module" do
            described_module().handle_info(message(), state())
            expect(module()) |> to_not(accepted(:handle_prepared_to_stopped))
          end

          it "should call handle_stopped_to_prepared(ctx, internal_state) callback on element's module" do
            described_module().handle_info(message(), state())

            expect(module())
            |> to(
              accepted(:handle_stopped_to_prepared, [ctx_playback_change(), internal_state()])
            )
          end

          it "should call handle_prepared_to_playing(ctx, internal_state) callback on element's module with internal state updated by previous handle_stopped_to_prepared call" do
            described_module().handle_info(message(), state())

            expect(module())
            |> to(
              accepted(:handle_prepared_to_playing, [
                ctx_playback_change(),
                %{internal_state() | a: 2}
              ])
            )
          end
        end

        context "and all callbacks have returned {:ok, state()}" do
          let :new_internal_state, do: %{key: :new_value}

          before do
            allow module()
                  |> to(
                    accept(:handle_prepared_to_playing, fn _, received_internal_state ->
                      {:ok, received_internal_state}
                    end)
                  )

            allow module()
                  |> to(
                    accept(:handle_stopped_to_prepared, fn _, _received_internal_state ->
                      {:ok, new_internal_state()}
                    end)
                  )

            allow module()
                  |> to(
                    accept(:handle_prepared_to_stopped, fn _, received_internal_state ->
                      {:ok, received_internal_state}
                    end)
                  )
          end

          it "should not call handle_prepared_to_stopped callback on element's module" do
            described_module().handle_info(message(), state())
            expect(module()) |> to_not(accepted(:handle_prepared_to_stopped))
          end

          it "should call handle_stopped_to_prepared(_ctx, internal_state) callback on element's module" do
            described_module().handle_info(message(), state())

            expect(module())
            |> to(
              accepted(:handle_stopped_to_prepared, [ctx_playback_change(), internal_state()])
            )
          end

          it "should call handle_prepared_to_playing(ctx, internal_state) callback on element's module with state updated by handle_stopped_to_prepared" do
            described_module().handle_info(message(), state())

            expect(module())
            |> to(
              accepted(:handle_prepared_to_playing, [ctx_playback_change(), new_internal_state()])
            )
          end

          it "it return {:reply, :ok, state()} with internal state updated by handle_stopped_to_prepared" do
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
            allow module()
                  |> to(
                    accept(:handle_prepared_to_playing, fn _, _state ->
                      {:ok, new_internal_state()}
                    end)
                  )

            allow module()
                  |> to(
                    accept(:handle_stopped_to_prepared, fn _, received_internal_state ->
                      {:ok, received_internal_state}
                    end)
                  )

            allow module()
                  |> to(
                    accept(:handle_playing_to_prepared, fn _, received_internal_state ->
                      {:ok, received_internal_state}
                    end)
                  )

            allow module()
                  |> to(
                    accept(:handle_prepared_to_stopped, fn _, received_internal_state ->
                      {:ok, received_internal_state}
                    end)
                  )
          end

          it "should not call handle_prepared_to_stopped callback on element's module" do
            described_module().handle_info(message(), state())
            expect(module()) |> to_not(accepted(:handle_prepared_to_stopped))
          end

          it "should not call handle_stopped_to_prepared callback on element's module" do
            described_module().handle_info(message(), state())
            expect(module()) |> to_not(accepted(:handle_stopped_to_prepared))
          end

          it "should not call handle_playing_to_prepared callback on element's module" do
            described_module().handle_info(message(), state())
            expect(module()) |> to_not(accepted(:handle_playing_to_prepared))
          end

          it "should call handle_prepared_to_playing(ctx, internal_state) callback on element's module" do
            described_module().handle_info(message(), state())

            expect(module())
            |> to(
              accepted(:handle_prepared_to_playing, [ctx_playback_change(), internal_state()])
            )
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
          allow module()
                |> to(
                  accept(:handle_prepared_to_playing, fn _, received_internal_state ->
                    {:ok, received_internal_state}
                  end)
                )

          allow module()
                |> to(
                  accept(:handle_stopped_to_prepared, fn _, received_internal_state ->
                    {:ok, received_internal_state}
                  end)
                )

          allow module()
                |> to(
                  accept(:handle_playing_to_prepared, fn _, received_internal_state ->
                    {:ok, received_internal_state}
                  end)
                )

          allow module()
                |> to(
                  accept(:handle_prepared_to_stopped, fn _, received_internal_state ->
                    {:ok, received_internal_state}
                  end)
                )
        end

        it "should not call handle_prepared_to_stopped callback on element's module" do
          described_module().handle_info(message(), state())
          expect(module()) |> to_not(accepted(:handle_prepared_to_stopped))
        end

        it "should not call handle_stopped_to_prepared callback on element's module" do
          described_module().handle_info(message(), state())
          expect(module()) |> to_not(accepted(:handle_stopped_to_prepared))
        end

        it "should not call handle_playing_to_prepared callback on element's module" do
          described_module().handle_info(message(), state())
          expect(module()) |> to_not(accepted(:handle_playing_to_prepared))
        end

        it "should not call handle_prepared_to_playing callback on element's module" do
          described_module().handle_info(message(), state())
          expect(module()) |> to_not(accepted(:handle_prepared_to_playing))
        end

        pending "should return {:reply, :noop, state()} with unmodified state"
      end
    end

    context "change playback state to prepared" do
      let :message, do: Message.new(:change_playback_state, :prepared)
      let :module, do: TrivialFilter
      let :internal_state, do: %{}

      let :state,
        do: %State{module: module(), playback: playback(), internal_state: internal_state()}

      let :ctx_playback_change, do: %CallbackContext.PlaybackChange{}

      context "and current playback state is :stopped" do
        let :playback, do: %Playback{state: :stopped}

        pending "and at least one of the callbacks has returned an error"

        context "and all callbacks have returned {:ok, state()}" do
          let :new_internal_state, do: :new_int_state

          before do
            allow module()
                  |> to(
                    accept(:handle_prepared_to_playing, fn _, received_internal_state ->
                      {:ok, received_internal_state}
                    end)
                  )

            allow module()
                  |> to(
                    accept(:handle_stopped_to_prepared, fn _, _state ->
                      {:ok, new_internal_state()}
                    end)
                  )

            allow module()
                  |> to(
                    accept(:handle_prepared_to_stopped, fn _, received_internal_state ->
                      {:ok, received_internal_state}
                    end)
                  )
          end

          it "should not call handle_prepared_to_stopped callback on element's module" do
            described_module().handle_info(message(), state())
            expect(module()) |> to_not(accepted(:handle_prepared_to_stopped))
          end

          it "should call handle_playing_to_prepared(ctx, internal_state) callback on element's module" do
            described_module().handle_info(message(), state())

            expect(module())
            |> to(
              accepted(:handle_stopped_to_prepared, [ctx_playback_change(), internal_state()])
            )
          end

          it "should not call handle_prepared_to_playing callback on element's module" do
            described_module().handle_info(message(), state())
            expect(module()) |> to_not(accepted(:handle_prepared_to_playing))
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
          allow module()
                |> to(
                  accept(:handle_prepared_to_playing, fn _, received_internal_state ->
                    {:ok, received_internal_state}
                  end)
                )

          allow module()
                |> to(
                  accept(:handle_stopped_to_prepared, fn _, received_internal_state ->
                    {:ok, received_internal_state}
                  end)
                )

          allow module()
                |> to(
                  accept(:handle_playing_to_prepared, fn _, received_internal_state ->
                    {:ok, received_internal_state}
                  end)
                )

          allow module()
                |> to(
                  accept(:handle_prepared_to_stopped, fn _, received_internal_state ->
                    {:ok, received_internal_state}
                  end)
                )
        end

        it "should not call handle_prepared_to_stopped callback on element's module" do
          described_module().handle_info(message(), state())
          expect(module()) |> to_not(accepted(:handle_prepared_to_stopped))
        end

        it "should not call handle_stopped_to_prepared callback on element's module" do
          described_module().handle_info(message(), state())
          expect(module()) |> to_not(accepted(:handle_stopped_to_prepared))
        end

        it "should not call handle_playing_to_prepared callback on element's module" do
          described_module().handle_info(message(), state())
          expect(module()) |> to_not(accepted(:handle_playing_to_prepared))
        end

        it "should not call handle_prepared_to_playing callback on element's module" do
          described_module().handle_info(message(), state())
          expect(module()) |> to_not(accepted(:handle_prepared_to_playing))
        end

        pending "should return {:reply, :noop, state()} with unmodified state"
      end

      context "and current playback state is :playing" do
        let :playback, do: %Playback{state: :playing}
        let :ctx_playback_change, do: %CallbackContext.PlaybackChange{}

        pending "and at least one of the callbacks has returned an error"

        context "and all callbacks have returned {:ok, state()}" do
          let :new_internal_state, do: :new_satete

          before do
            allow module()
                  |> to(
                    accept(:handle_prepared_to_playing, fn _, received_internal_state ->
                      {:ok, received_internal_state}
                    end)
                  )

            allow module()
                  |> to(
                    accept(:handle_playing_to_prepared, fn _, _state ->
                      {:ok, new_internal_state()}
                    end)
                  )

            allow module()
                  |> to(
                    accept(:handle_prepared_to_stopped, fn _, received_internal_state ->
                      {:ok, received_internal_state}
                    end)
                  )
          end

          it "should not call handle_prepared_to_stopped callback on element's module" do
            described_module().handle_info(message(), state())
            expect(module()) |> to_not(accepted(:handle_prepared_to_stopped))
          end

          it "should call handle_playing_to_prepared(ctx, internal_state) callback on element's module" do
            described_module().handle_info(message(), state())

            expect(module())
            |> to(
              accepted(:handle_playing_to_prepared, [ctx_playback_change(), internal_state()])
            )
          end

          it "should not call handle_prepared_to_playing callback on element's module" do
            described_module().handle_info(message(), state())
            expect(module()) |> to_not(accepted(:handle_prepared_to_playing))
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

    context "change playback state to stopped" do
      let :message, do: Message.new(:change_playback_state, :stopped)
      let :module, do: TrivialFilter
      let :internal_state, do: %{}
      let :ctx_playback_change, do: %CallbackContext.PlaybackChange{}

      let :state,
        do: %State{module: module(), playback: playback(), internal_state: internal_state()}

      context "and current playback state is :playing" do
        let :playback, do: %Playback{state: :playing}

        pending "and at least one of the callbacks has returned an error"

        context "and all callbacks have returned {:ok, state()}" do
          let :new_internal_state, do: %{value: :new_value}

          before do
            allow module()
                  |> to(
                    accept(:handle_prepared_to_playing, fn _, received_internal_state ->
                      {:ok, received_internal_state}
                    end)
                  )

            allow module()
                  |> to(
                    accept(:handle_playing_to_prepared, fn _, received_internal_state ->
                      {:ok, received_internal_state}
                    end)
                  )

            allow module()
                  |> to(
                    accept(:handle_prepared_to_stopped, fn _, _ -> {:ok, new_internal_state()} end)
                  )
          end

          it "should call handle_prepared_to_stopped callback on element's module" do
            described_module().handle_info(message(), state())

            expect(module())
            |> to(
              accepted(:handle_prepared_to_stopped, [ctx_playback_change(), internal_state()])
            )
          end

          it "should call handle_playing_to_prepared(:playing, internal_state) callback on element's module" do
            described_module().handle_info(message(), state())

            expect(module())
            |> to(
              accepted(:handle_playing_to_prepared, [ctx_playback_change(), internal_state()])
            )
          end

          it "should not call handle_prepared_to_playing callback on element's module" do
            described_module().handle_info(message(), state())
            expect(module()) |> to_not(accepted(:handle_prepared_to_playing))
          end

          it "should return {:reply, :ok, state()} with internal state updated by handle_prepared_to_stopped" do
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
            allow module()
                  |> to(
                    accept(:handle_prepared_to_playing, fn _, received_internal_state ->
                      {:ok, received_internal_state}
                    end)
                  )

            allow module()
                  |> to(
                    accept(:handle_stopped_to_prepared, fn _, received_internal_state ->
                      {:ok, received_internal_state}
                    end)
                  )

            allow module()
                  |> to(
                    accept(:handle_playing_to_prepared, fn _, received_internal_state ->
                      {:ok, received_internal_state}
                    end)
                  )

            allow module()
                  |> to(
                    accept(:handle_prepared_to_stopped, fn _, _state ->
                      {:ok, new_internal_state()}
                    end)
                  )
          end

          it "should call handle_prepared_to_stopped callback on element's module" do
            described_module().handle_info(message(), state())

            expect(module())
            |> to(
              accepted(:handle_prepared_to_stopped, [ctx_playback_change(), internal_state()])
            )
          end

          it "should not call handle_stopped_to_prepared and handle_playing_to_prepared callbacks on element's module" do
            described_module().handle_info(message(), state())
            expect(module()) |> to_not(accepted(:handle_stopped_to_prepared))
            expect(module()) |> to_not(accepted(:handle_playing_to_prepared))
          end

          it "should not call handle_prepared_to_playing callback on element's module" do
            described_module().handle_info(message(), state())
            expect(module()) |> to_not(accepted(:handle_prepared_to_playing))
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
          allow module()
                |> to(
                  accept(:handle_prepared_to_playing, fn _, received_internal_state ->
                    {:ok, received_internal_state}
                  end)
                )

          allow module()
                |> to(
                  accept(:handle_stopped_to_prepared, fn _, received_internal_state ->
                    {:ok, received_internal_state}
                  end)
                )

          allow module()
                |> to(
                  accept(:handle_playing_to_prepared, fn _, received_internal_state ->
                    {:ok, received_internal_state}
                  end)
                )

          allow module()
                |> to(
                  accept(:handle_prepared_to_stopped, fn _, received_internal_state ->
                    {:ok, received_internal_state}
                  end)
                )
        end

        it "should not call handle_prepared_to_stopped callback on element's module" do
          described_module().handle_info(message(), state())
          expect(module()) |> to_not(accepted(:handle_prepared_to_stopped))
        end

        it "should not call handle_stopped_to_prepared and handle_playing_to_prepared callbacks on element's module" do
          described_module().handle_info(message(), state())
          expect(module()) |> to_not(accepted(:handle_stopped_to_prepared))
          expect(module()) |> to_not(accepted(:handle_playing_to_prepared))
        end

        it "should not call handle_prepared_to_playing callback on element's module" do
          described_module().handle_info(message(), state())
          expect(module()) |> to_not(accepted(:handle_prepared_to_playing))
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
    context "if message is Message.new(:set_watcher, pid)" do
      let :new_watcher, do: self()
      let :message, do: Message.new(:set_watcher, new_watcher())
      let :state, do: %State{module: TrivialFilter, watcher: watcher()}

      context "and current watcher is nil" do
        let :watcher, do: nil

        it "should return {:noreply, :state()} with watcher set to the new watcher" do
          expect(described_module().handle_call(message(), self(), state()))
          |> to(eq {:reply, :ok, %{state() | watcher: new_watcher()}})
        end
      end

      context "and current watcher is set to the same watcher as requested" do
        let :watcher, do: new_watcher()

        it "should return {:reply, :ok, state()} with watcher set to the new watcher" do
          expect(described_module().handle_call(message(), self(), state()))
          |> to(eq {:reply, :ok, %{state() | watcher: new_watcher()}})
        end
      end
    end
  end
end
