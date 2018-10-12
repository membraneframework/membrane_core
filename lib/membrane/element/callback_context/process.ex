defmodule Membrane.Element.CallbackContext.Process do
  @moduledoc """
  Structure representing a context that is passed to the element when new buffer arrives.
  """
  @behaviour Membrane.Element.CallbackContext

  @type t :: %Membrane.Element.CallbackContext.Process{
          playback_state: Membrane.Core.Playback.state_t(),
          caps: Membrane.Caps.t(),
          output_pad: nil,
          output_pad_caps: Membrane.Caps.t()
        }

  defstruct playback_state: nil,
            caps: nil,
            output_pad: nil,
            output_pad_caps: nil

  @impl true
  defmacro from_state(state, entries) do
    quote do
      %unquote(__MODULE__){
        unquote_splicing(entries),
        playback_state: unquote(state).playback.state
      }
    end
  end
end
