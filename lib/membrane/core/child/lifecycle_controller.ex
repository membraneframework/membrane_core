defmodule Membrane.Core.Child.LifecycleController do
  @moduledoc false
  use Bunch

  alias Membrane.{Clock, Pad}
  alias Membrane.Core.{Child, Message}
  alias Membrane.Core.Child.PadModel

  require Message
  require PadModel

  @doc """
  Stores demand unit of subsequent element pad.
  """
  @spec handle_demand_unit(demand_unit :: atom, Pad.ref_t(), Child.state_t()) ::
          {:ok, Child.state_t()}
  def handle_demand_unit(demand_unit, pad_ref, state) do
    PadModel.assert_data!(state, pad_ref, %{direction: :output})

    state
    |> PadModel.set_data!(pad_ref, [:other_demand_unit], demand_unit)
    ~> {:ok, &1}
  end

  @spec handle_controlling_pid(pid, Child.state_t()) :: {:ok, Child.state_t()}
  def handle_controlling_pid(pid, state), do: {:ok, %{state | controlling_pid: pid}}

  @spec handle_watcher(pid, Child.state_t()) :: {{:ok, %{clock: Clock.t()}}, Child.state_t()}
  def handle_watcher(watcher, state) do
    %{synchronization: %{clock: clock}} = state
    {{:ok, %{clock: clock}}, %{state | watcher: watcher}}
  end

  def unlink(state) do
    state.pads.data
    |> Map.values()
    |> Enum.each(&Message.send(&1.pid, :handle_unlink, &1.other_ref))
  end
end
