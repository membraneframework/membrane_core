defmodule Membrane.Core.ParentAction do
  alias Membrane.CallbackError
  alias Membrane.Core.ParentState
  alias Membrane.Core.Message

  use Bunch

  @typedoc """
  Action that sends a message to element identified by name.
  """
  @type forward_action_t :: {:forward, {Element.name_t(), Notification.t()}}

  @typedoc """
  Action that instantiates elements and links them according to `Membrane.Pipeline.Spec`.

  Elements playback state is changed to the current pipeline state.
  `c:handle_spec_started` callback is executed once it happens.
  """
  @type spec_action_t :: {:spec, Spec.t()}

  @typedoc """
  Action that stops, unlinks and removes specified child/children from pipeline.
  """
  @type remove_child_action_t :: {:remove_child, Element.name_t() | [Element.name_t()]}

  @typedoc """
  Type describing actions that can be returned from pipeline callbacks.

  Returning actions is a way of pipeline interaction with its elements and
  other parts of framework.
  """
  @type t :: forward_action_t | spec_action_t | remove_child_action_t

  def handle_forward(elementname, message, state) do
    with {:ok, pid} <- state |> ParentState.get_child_pid(elementname) do
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
           |> Bunch.Enum.try_map(&ParentState.get_child_pid(state, &1)) do
      pids |> Enum.each(&Message.send(&1, :prepare_shutdown))
      :ok
    end
    ~> {&1, state}
  end

  def handle_unknown_action(action, callback, module) do
    raise CallbackError, kind: :invalid_action, action: action, callback: {module, callback}
  end
end
