defmodule Membrane.Core.Child.LifecycleController do
  @moduledoc false
  use Bunch

  alias Membrane.{Clock, Pad}
  alias Membrane.Core.{Bin, Element}
  alias Membrane.Core.Child.PadModel

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

  @spec handle_watcher(pid, state()) :: {{:ok, %{clock: Clock.t()}}, state()}
  def handle_watcher(watcher, state) do
    %{synchronization: %{clock: clock}} = state
    {{:ok, %{clock: clock}}, %{state | watcher: watcher}}
  end
end
