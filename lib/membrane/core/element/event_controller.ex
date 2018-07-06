defmodule Membrane.Core.Element.EventController do
  alias Membrane.{Core, Element, Event}
  alias Core.{CallbackHandler, PullBuffer}
  alias Core.Element.{ActionHandler, PadModel}
  alias Element.Context
  require PadModel
  use Core.Element.Log
  use Membrane.Helper

  def handle_event(pad_name, event, state) do
    pad_data = PadModel.get_data!(pad_name, state)

    if event.mode == :sync && pad_data.mode == :pull && pad_data.direction == :sink &&
         pad_data.buffer |> PullBuffer.empty?() |> Kernel.not() do
      PadModel.update_data(
        pad_name,
        :buffer,
        &(&1 |> PullBuffer.store(:event, event)),
        state
      )
    else
      exec_handle_event(pad_name, event, state)
    end
  end

  def exec_handle_event(pad_name, event, state) do
    with {{:ok, :handle}, state} <- parse_event(pad_name, event, state),
         {:ok, state} <- do_exec_handle_event(pad_name, event, state) do
      {:ok, state}
    else
      {{:ok, :ignore}, state} ->
        debug("ignoring event #{inspect(event)}", state)
        {:ok, state}

      {:error, reason} ->
        warn_error("Error while handling event", {:handle_event, reason}, state)
    end
  end

  defp parse_event(pad_name, %Event{type: :sos}, state) do
    with %{direction: :sink, sos: false} <- PadModel.get_data!(pad_name, state) do
      {:ok, state} = PadModel.set_data(pad_name, :sos, true, state)
      {{:ok, :handle}, state}
    else
      %{direction: :source} -> {:error, {:received_sos_through_source, pad_name}}
      %{sos: true} -> {:error, {:sos_already_received, pad_name}}
    end
  end

  defp parse_event(pad_name, %Event{type: :eos}, state) do
    with %{direction: :sink, sos: true, eos: false} <- PadModel.get_data!(pad_name, state) do
      {:ok, state} = PadModel.set_data(pad_name, :eos, true, state)
      {{:ok, :handle}, state}
    else
      %{direction: :source} -> {:error, {:received_eos_through_source, pad_name}}
      %{eos: true} -> {:error, {:eos_already_received, pad_name}}
      %{sos: false} -> {{:ok, :ignore}, state}
    end
  end

  # FIXME: solve it using pipeline messages, not events
  defp parse_event(_pad_name, %Event{type: :dump_state}, state) do
    IO.puts("""
    state dump for #{inspect(state.name)} at #{inspect(self())}
    state:
    #{inspect(state)}
    info:
    #{inspect(:erlang.process_info(self()))}
    """)

    {{:ok, :handle}, state}
  end

  defp parse_event(_pad_name, _event, state), do: {{:ok, :handle}, state}

  defp do_exec_handle_event(pad_name, event, state) do
    data = PadModel.get_data!(pad_name, state)
    context = %Context.Event{caps: data.caps}

    CallbackHandler.exec_and_handle_callback(
      :handle_event,
      ActionHandler,
      %{direction: data.direction},
      [pad_name, event, context],
      state
    )
  end
end
