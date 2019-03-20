defmodule Membrane.Core.Playback do
  @moduledoc false
  # This module defines available playback states and struct that is held
  # internally by every module having playback state.

  defstruct state: :stopped,
            pending_state: nil,
            target_state: :stopped,
            target_locked?: false,
            async_state_change: false

  @type t :: %__MODULE__{
          state: state_t,
          pending_state: state_t | nil,
          target_state: state_t,
          target_locked?: boolean,
          async_state_change: boolean
        }

  @type state_t :: :stopped | :prepared | :playing

  defguard is_playback_state(atom) when atom in [:stopped, :prepared, :playing]
end
