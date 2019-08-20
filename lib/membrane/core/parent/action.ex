defmodule Membrane.Core.Parent.Action do
  @moduledoc false
  alias Membrane.CallbackError
  alias Membrane.Core.{Parent, Message}

  use Bunch

  def handle_forward(elementname, message, state) do
    with {:ok, pid} <- state |> Parent.ChildrenModel.get_child_pid(elementname) do
      send(pid, message)
      {:ok, state}
    else
      {:error, reason} ->
        {{:error, {:cannot_forward_message, [element: elementname, message: message], reason}},
         state}
    end
  end

  def handle_remove_child(children, state) do
    with {:ok, pids} <-
           children
           |> Bunch.listify()
           |> Bunch.Enum.try_map(&Parent.ChildrenModel.get_child_pid(state, &1)) do
      pids |> Enum.each(&Message.send(&1, :prepare_shutdown))
      :ok
    end
    ~> {&1, state}
  end

  def handle_unknown_action(action, callback, module) do
    raise CallbackError, kind: :invalid_action, action: action, callback: {module, callback}
  end
end
