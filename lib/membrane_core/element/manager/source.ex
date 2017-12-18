defmodule Membrane.Element.Manager.Source do
  @moduledoc """
  Base module to be used by all elements that are sources, in other words,
  elements that produce the buffers. Some examples might be: a file reader,
  a sound card input.

  ## Callbacks

  As for all base elements in the Membrane Framework, lifecycle of sinks is
  defined by set of callbacks. All of them have names with the `handle_` prefix.
  They are used to define reaction to certain events that happen during runtime,
  and indicate what actions frawork should undertake as a result, besides
  executing element-specific code.

  ## Actions

  All callbacks have to return a value.

  If they were successful they return `{:ok, actions, new_state}` tuple,
  where `actions` is a list of actions to be undertaken by the framework after
  the callback has finished its execution.

  Each action may be one of the following:

  * `{:buffer, {pad_name, buffer}}` - it will cause sending given buffer
    from pad of given name to its peer.
  * `{:caps, {pad_name, caps}}` - it will cause sending new caps for pad of
    given name.
  * `{:event, {pad_name, event}}` - it will cause sending given event
    from pad of given name to its peer.
  * `{:message, message}` - it will cause sending given message to the element's
    message bus (usually a pipeline) if any is defined,

  ## Demand

  If Element.Manager has source pads in the pull mode, the demand will be triggered
  by sinks. The `handle_demand/2` callback will be then invoked but
  should not return more than one buffer per one `handle_demand/2` call.
  In such case, if Element.Manager is holding more data than for one buffer,
  the remaining data should remain cached in the element's state and released
  upon next `handle_demand/2`.

  If Element.Manager has source pads in the push mode, it is allowed to generate
  buffers at any time.

  ## Example

  The simplest possible source Element.Manager that has pad working in the pull mode,
  looks like the following:

      defmodule Membrane.Element.Manager.Sample.Source do
        use Membrane.Element.Manager.Base.Source

        def_known_source_pads %{
          :source => {:always, :pull, :any}
        }

        # Private API

        @doc false
        def handle_demand(_pad, state) do
          # Produce one buffer in response to demand
          {:ok, [
            {:buffer, {:source, %Membrane.Buffer{payload: "test"}}}
          ], state}
        end
      end

  ## See also

  * `Membrane.Element.Manager.Base.Mixin.CommonBehaviour` - for more callbacks.
  """

  use Membrane.Element.Manager.Log
  alias Membrane.{Element, Event}
  alias Membrane.Element.Manager.{Action, Common, State}
  alias Membrane.Element.Context
  use Membrane.Element.Manager.Common



  # Private API

  def handle_action({:buffer, {pad_name, buffer}}, cb, _params, state)
  when Common.is_pad_name(pad_name) do
    Action.send_buffer(pad_name, buffer, cb, state)
  end

  def handle_action({:caps, {pad_name, caps}}, _cb, _params, state)
  when Common.is_pad_name(pad_name) do
    Action.send_caps(pad_name, caps, state)
  end

  def handle_action({:redemand, src_name}, cb, _params, state)
  when Common.is_pad_name(src_name) and cb != :handle_demand do
    Action.handle_redemand(src_name, state)
  end

  def handle_action(action, callback, params, state) do
    available_actions = [
        "{:buffer, {pad_name, buffers}}",
        "{:caps, {pad_name, caps}}",
        "{:redemand, source_name}"
          |> (provided that: callback != :handle_demand),
      ] ++ Common.available_actions
    handle_invalid_action action, callback, params, available_actions, __MODULE__, state
  end

  def handle_redemand(src_name, state) do
    handle_demand src_name, 0, state
  end

  def handle_demand(pad_name, size, state) do
    {{:ok, stored_size}, state} = state
      |> State.get_update_pad_data(:source, pad_name, :demand, &{{:ok, &1}, &1+size})

    cond do
      stored_size + size <= 0 ->
        debug """
          Demand handler: not executing handle_demand, as demand is not
          greater than 0
          """, state
        {:ok, state}
      state |> State.get_pad_data!(:source, pad_name, :eos) ->
        debug """
          Demand handler: not executing handle_demand, as EoS has already been sent
          """, state
        {:ok, state}
      true ->
        %{caps: caps, options: %{other_demand_in: demand_in}} =
            state |> State.get_pad_data!(:source, pad_name)
        context = %Context.Demand{caps: caps}
        exec_and_handle_callback(
          :handle_demand, [pad_name, size + min(0, stored_size), demand_in, context], state)
            |> or_warn_error("""
              Demand arrived from pad #{inspect pad_name}, but error happened while
              handling it.
              """, state)
    end
  end


  def handle_event(mode, :source, pad_name, event, state) do
    with \
      {:ok, state} <- Common.handle_event(mode, :source, pad_name, event, state)
    do do_handle_event pad_name, event, state
    end
  end

  defp do_handle_event(_pad_name, %Event{type: :eos}, state) do
    Element.do_change_playback_state :stopped, state
  end
  defp do_handle_event(_pad_name, _event, state), do: {:ok, state}

  def handle_pad_added(name, :source, state) do
    context = %Context.PadAdded{
      direction: :source,
    }
    Common.handle_pad_added([name, context], state)
  end

end
