defmodule Membrane.Core.Parent.Action do
  @moduledoc false
  alias Bunch.Type
  alias Membrane.{CallbackError, Child}
  alias Membrane.Core
  alias Core.{Parent, Message, Bin, Pipeline}
  alias Parent.ChildrenController

  use Bunch

  @type state_t :: Bin.State.t() | Pipeline.State.t()

  @spec handle_forward(Child.name_t(), any, state_t()) :: Type.stateful_try_t(state_t)
  def handle_forward(element_name, message, state) do
    with {:ok, %{pid: pid}} <- state |> Parent.ChildrenModel.get_child_data(element_name) do
      send(pid, message)
      {:ok, state}
    else
      {:error, reason} ->
        {{:error, {:cannot_forward_message, [element: element_name, message: message], reason}},
         state}
    end
  end

  @spec handle_remove_child(Child.name_t() | [Child.name_t()], state_t()) ::
          Type.stateful_try_t(state_t)
  def handle_remove_child(children, state) do
    children = children |> Bunch.listify()

    {:ok, state} =
      if state.clock_provider.provider in children do
        %{state | clock_provider: %{clock: nil, provider: nil, choice: :auto}}
        |> ChildrenController.choose_clock()
      else
        {:ok, state}
      end

    with {:ok, data} <-
           children |> Bunch.Enum.try_map(&Parent.ChildrenModel.get_child_data(state, &1)) do
      data |> Enum.each(&Message.send(&1.pid, :prepare_shutdown))
      :ok
    end
    ~> {&1, state}
  end

  @spec handle_unknown_action(Membrane.Parent.Action.t(), atom, module) :: no_return()
  def handle_unknown_action(action, callback, module) do
    raise CallbackError, kind: :invalid_action, action: action, callback: {module, callback}
  end
end
