defmodule Membrane.Pipeline.State do
  @moduledoc false
  # Structure representing state of a pipeline. It is a part of the private API.
  # It does not represent state of pipelines you construct, it's a state used
  # internally in Membrane.

  alias Membrane.Core.{Playback, Playbackable}
  alias Membrane.Element
  alias Bunch.Type
  use Bunch

  @derive Playbackable

  @type t :: %__MODULE__{
          internal_state: internal_state_t | nil,
          playback: Playback.t(),
          module: module,
          children: children_t,
          pending_pids: MapSet.t(pid),
          terminating?: boolean
        }

  @type internal_state_t :: map | struct
  @type child_t :: {Element.name_t(), pid}
  @type children_t :: %{Element.name_t() => pid}

  defstruct internal_state: nil,
            module: nil,
            children: %{},
            playback: %Playback{},
            pending_pids: MapSet.new(),
            terminating?: false,
            clock_provider: %{clock: nil, provider: nil, choice: :auto},
            clock_proxy: nil

  @spec add_child(t, Element.name_t(), pid) :: Type.stateful_try_t(t)
  def add_child(%__MODULE__{children: children} = state, child, pid) do
    if Map.has_key?(children, child) do
      {{:error, {:duplicate_child, child}}, state}
    else
      {:ok, %__MODULE__{state | children: children |> Map.put(child, pid)}}
    end
  end

  # @spec get_child_pid(t, Element.name_t()) :: Type.try_t(pid)
  def get_child_data(%__MODULE__{children: children}, child) do
    children[child] |> Bunch.error_if_nil({:unknown_child, child})
  end

  @spec pop_child(t, Element.name_t()) :: Type.stateful_try_t(pid, t)
  def pop_child(%__MODULE__{children: children} = state, child) do
    {pid, children} = children |> Map.pop(child)

    with {:ok, pid} <- pid |> Bunch.error_if_nil({:unknown_child, child}) do
      state = %__MODULE__{state | children: children}
      {{:ok, pid}, state}
    end
  end

  @spec get_children_names(t) :: [Element.name_t()]
  def get_children_names(%__MODULE__{children: children}) do
    children |> Map.keys()
  end

  @spec get_children(t) :: children_t
  def get_children(%__MODULE__{children: children}) do
    children
  end
end
