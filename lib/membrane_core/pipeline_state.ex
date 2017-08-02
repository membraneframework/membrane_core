defmodule Membrane.Pipeline.State do
  @moduledoc false
  # Structure representing state of a pipeline. It is a part of the private API.
  # It does not represent state of pipelines you construct, it's a state used
  # internally in Membrane.

  use Membrane.Helper
  alias __MODULE__

  @type t :: %Membrane.Pipeline.State{
    internal_state: any,
    playback_state: Membrane.Mixins.Playback.state_t,
    module: module,
    children_to_pids: %{required([Membrane.Element.name_t]) => pid},
    pids_to_children: %{required(pid) => Membrane.Element.name_t},
  }

  defstruct \
    internal_state: nil,
    module: nil,
    children_to_pids: %{},
    pids_to_children: %{},
    children_pad_nos: %{},
    playback_state: :stopped


    def get_child(%State{pids_to_children: pids_to_children}, child)
    when is_pid(child) do
      pids_to_children
        |> Map.get(child)
        ~> (nil -> {:error, :unknown_child}; v -> {:ok, v})
    end

    def get_child(%State{children_to_pids: children_to_pids}, child) do
      children_to_pids
        |> Map.get(child)
        ~> (nil -> {:error, :unknown_child}; [h|_t] -> {:ok, h})
    end
end
