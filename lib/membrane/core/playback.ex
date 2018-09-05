defmodule Membrane.Core.Playback do
  @moduledoc """
  Behaviour for modules that have playback state, i.e. elements and pipelines

  There are three playback states: :stopped, :prepared and :playing.
  Playback state always changes only one step at once in this order, and can
  be handled by `handle_prepare_to_play`, `handle_prepare_to_stop`, `handle_play` and `handle_stop` callbacks.
  """
  use Bunch

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
end
