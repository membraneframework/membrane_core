defmodule Membrane.Core.Child.LifecycleController do
  use Bunch

  alias Membrane.Pad
  alias Membrane.Core.PadModel

  require PadModel

  @type state :: Bin.State.t() | Element.State.t()

  @doc """
  Stores demand unit of subsequent element pad.
  """
  @spec handle_demand_unit(demand_unit :: atom, Pad.ref_t(), state()) :: {:ok, state()}
  def handle_demand_unit(demand_unit, pad_ref, state) do
    PadModel.assert_data!(state, pad_ref, %{direction: :output})

    state
    |> PadModel.set_data!(pad_ref, [:other_demand_unit], demand_unit)
    ~> {:ok, &1}
  end

  @spec handle_controlling_pid(pid, state()) :: {:ok, state()}
  def handle_controlling_pid(pid, state), do: {:ok, %{state | controlling_pid: pid}}

  @spec handle_watcher(pid, state()) :: {:ok, state()}
  def handle_watcher(watcher, state), do: {:ok, %{state | watcher: watcher}}
end
