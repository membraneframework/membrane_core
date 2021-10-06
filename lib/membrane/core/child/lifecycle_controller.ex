defmodule Membrane.Core.Child.LifecycleController do
  @moduledoc false
  use Bunch

  alias Membrane.Core.{Child, Message}
  alias Membrane.Core.Child.PadModel

  require Message
  require PadModel

  @spec handle_controlling_pid(pid, Child.state_t()) :: {:ok, Child.state_t()}
  def handle_controlling_pid(pid, state), do: {:ok, %{state | controlling_pid: pid}}

  @spec unlink(Child.state_t()) :: :ok
  def unlink(state) do
    state.pads.data
    |> Map.values()
    |> Enum.each(&Message.send(&1.pid, :handle_unlink, &1.other_ref))
  end
end
