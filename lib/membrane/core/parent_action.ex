defmodule Membrane.Core.ParentAction do
  @moduledoc """
  This module consists of common for bin and pipeline types and functions connected to actions.
  """
  alias Membrane.CallbackError
  alias Membrane.Core.Parent
  alias Membrane.Core.Message
  alias Membrane.Notification
  alias Membrane.Pipeline
  alias Membrane.Bin
  alias Membrane.Core.ChildrenController

  use Bunch

  @typedoc """
  Action that sends a message to element identified by name.
  """
  @type forward_action_t :: {:forward, {ChildrenController.child_name_t(), Notification.t()}}

  @typedoc """
  Action that instantiates elements and links them according to `Membrane.Core.ParentSpec`.

  Children's playback state is changed to the current parent state.
  `c:handle_spec_started` callback is executed once it happens.
  """
  @type spec_action_t :: {:spec, Pipeline.Spec.t() | Bin.Spec.t()}

  @typedoc """
  Action that stops, unlinks and removes specified child/children from their parent.
  """
  @type remove_child_action_t ::
          {:remove_child, ChildrenController.child_name_t() | [ChildrenController.child_name_t()]}

  @typedoc """
  Type describing actions that can be returned from parent callbacks.

  Returning actions is a way of pipeline/bin interaction with its elements and
  other parts of framework.
  """
  @type t :: forward_action_t | spec_action_t | remove_child_action_t

  def handle_forward(elementname, message, state) do
    with {:ok, pid} <- state |> Parent.State.get_child_pid(elementname) do
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
           |> Bunch.Enum.try_map(&Parent.State.get_child_pid(state, &1)) do
      pids |> Enum.each(&Message.send(&1, :prepare_shutdown))
      :ok
    end
    ~> {&1, state}
  end

  def handle_unknown_action(action, callback, module) do
    raise CallbackError, kind: :invalid_action, action: action, callback: {module, callback}
  end
end
