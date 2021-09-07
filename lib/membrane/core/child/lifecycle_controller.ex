defmodule Membrane.Core.Child.LifecycleController do
  @moduledoc false
  use Bunch

  alias Membrane.Core.{Child, Message}
  alias Membrane.Core.Child.PadModel

  require Message
  require PadModel

  @spec unlink(Child.state_t()) :: :ok
  def unlink(state) do
    state.pads.data
    |> Map.values()
    |> Enum.filter(& &1[:pid])
    |> Enum.each(&Message.send(&1.pid, :handle_unlink, &1.other_ref))
  end
end
