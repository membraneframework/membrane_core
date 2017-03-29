defmodule Membrane.Pad.Mode.Pull do
  @moduledoc false
  # Module contains logic that causes sink pads in the pull mode to actually
  # generate demand for new buffers and forward these buffers to the parent
  # element's handle_buffer callback so it can consume it.
  #
  # It enters a loop and demands new chunk of data after each call to the
  # handle_buffer callback of the parent element so if element is sink that
  # has limited throughput, and it is using blocking calls, it will limit
  # also throughput of the pipeline which is desired in many cases.


  use Membrane.Pad.Mode
  use Membrane.Mixins.Log


  @doc false
  def handle_init do
    {:ok, %{
      looping: false,
      active: false,
    }}
  end


  @doc false
  def handle_activate(_peer, :source, state) do
    # Do nothing regarding activation for source pads when in the pull mode.
    # They only react for incoming calls from sink pads.
    {:ok, %{state | active: true}}
  end

  def handle_activate(nil, :sink, state) do
    # Do nothing if we are sink pad but not linked yet. Loop will be started
    # then upon linking.
    {:ok, %{state | active: true}}
  end

  def handle_activate(_peer, :sink, state) do
    # If we are sink pad and we are linked, start loop.
    debug("Starting loop")
    iterate()
    {:ok, %{state | active: true, looping: true}}
  end


  @doc false
  def handle_link(_peer, :sink, %{active: true, looping: false} = state) do
    # If we are sink pad and we activated but not linked, start loop.
    debug("Starting loop")
    iterate()
    {:ok, %{state | looping: true}}
  end

  def handle_link(_peer, _direction, state) do
    {:ok, state}
  end


  @doc false
  def handle_call(:membrane_pull_demand, _peer, :source, state) do
    # This is the actual loop that responds to new buffers requests from the
    # subesequent element.
    debug("Demand: Response")

    # 1. Forward the demand to the parent element

    # {:ok, buffer} = GenServer.call(parent, whatever)
    buffer = %Membrane.Buffer{} # FIXME

    # 2. Reply
    {:reply, {:ok, buffer}, state}
  end


  @doc false
  def handle_other(:membrane_iterate, nil, :sink, state) do
    # Do nothing if peer is nil, probably we got unliked and there still
    # were some messages in the queue.
    {:ok, state}
  end

  def handle_other(:membrane_iterate, peer, :sink, state) do
    # This is the actual loop that requests new buffers from previous element.
    debug("Demand: Request")

    # 1. Determine demand from the parent element
    # element_module.handle_buffer(pad, caps, nil, internal_state)

    # 2. Demand data from the peer
    {:ok, buffer} = GenServer.call(peer, :membrane_pull_demand) # FIXME
    debug("Demand: Got #{inspect(buffer)}")

    # 3. Forward data to the parent element
    # element_module.handle_buffer(pad, caps, buffer, internal_state)

    # 4. Loop
    iterate()

    {:ok, state}
  end


  defp iterate, do: send(self(), :membrane_iterate)
end
