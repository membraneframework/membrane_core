defmodule Membrane.Core.ElementSpec do
  use ESpec, async: false

  alias Membrane.Core.{Message, Playback}
  alias Membrane.Core.Element.State
  alias Membrane.Element.CallbackContext
  alias Membrane.Support.Element.{TrivialFilter, TrivialSource}
  alias Membrane.Sync

  require CallbackContext.PlaybackChange
  require Message

  pending ".start_link/3"
  pending ".start/3"

  def start_element(module) do
    described_module().start_link(%{
      module: module,
      name: :name,
      user_options: %{},
      parent: self(),
      clock: nil,
      sync: Sync.no_sync()
    })
  end

  defmacrop catch_exit(call) do
    quote do
      Process.flag(:trap_exit, true)

      try do
        capture_log(fn -> unquote(call) end)
      catch
        :exit, {{exception, _}, _} -> exception
      end
    end
  end

  describe ".handle_info/3" do
    context "change playback state to playing" do
      let :message, do: Message.new(:change_playback_state, :playing)
      let :module, do: TrivialSource
      let :internal_state, do: %{a: 1}
      let :ctx_playback_change, do: state() |> CallbackContext.PlaybackChange.from_state()

      let :state,
        do: %{
          State.new(%{module: module(), name: :name, clock: nil, sync: nil})
          | playback: playback(),
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
                      {{:error, reason()}, %{received_internal_state | a: 3}}
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
        do: %{
          State.new(%{module: module(), name: :name, clock: nil, sync: nil})
          | playback: playback(),
            internal_state: internal_state()
        }

      let :ctx_playback_change, do: state() |> CallbackContext.PlaybackChange.from_state()

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
        let :ctx_playback_change, do: state() |> CallbackContext.PlaybackChange.from_state()

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
      let :ctx_playback_change, do: state() |> CallbackContext.PlaybackChange.from_state()

      let :state,
        do: %{
          State.new(%{module: module(), name: :name, clock: nil, sync: nil})
          | playback: playback(),
            internal_state: internal_state()
        }

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
    context "if message is Message.new(:handle_watcher, pid)" do
      let :new_watcher, do: self()
      let :message, do: Message.new(:handle_watcher, new_watcher())

      let :state,
        do: %{
          State.new(%{module: TrivialFilter, name: :name, clock: nil, sync: nil})
          | watcher: watcher()
        }

      context "and current watcher is nil" do
        let :watcher, do: nil

        it "should return {:noreply, :state()} with watcher set to the new watcher" do
          expect(described_module().handle_call(message(), self(), state()))
          |> to(eq {:reply, {:ok, %{clock: nil}}, %{state() | watcher: new_watcher()}})
        end
      end

      context "and current watcher is set to the same watcher as requested" do
        let :watcher, do: new_watcher()

        it "should return {:reply, :ok, state()} with watcher set to the new watcher" do
          expect(described_module().handle_call(message(), self(), state()))
          |> to(eq {:reply, {:ok, %{clock: nil}}, %{state() | watcher: new_watcher()}})
        end
      end
    end
  end
end
