defmodule Membrane.Core.Playback do
  @moduledoc false

  # This module defines available playback states and struct that is held
  # internally by every module having playback state.

  alias Membrane.PlaybackState

  defstruct state: :stopped,
            pending_state: nil,
            target_state: :stopped,
            target_locked?: false,
            async_state_change: false

  @type t :: %__MODULE__{
          state: PlaybackState.t(),
          pending_state: PlaybackState.t() | nil,
          target_state: PlaybackState.t(),
          target_locked?: boolean,
          async_state_change: boolean
        }

  def stable?(%__MODULE__{state: state, pending_state: nil, target_state: state}), do: true
  def stable?(%__MODULE__{}), do: false
end
