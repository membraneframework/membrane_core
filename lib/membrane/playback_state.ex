defmodule Membrane.PlaybackState do
  @moduledoc """
  Playback states describe the state of an element or a pipeline. There are following
  playback states:

   - `:stopped` - Idle. No resources should be initialized nor allocated.
   - `:prepared` - Ready for processing data. All necessary resources should be allocated and initialized.
   - `:playing` - Data is being processed.

  Every playback state change is done step-by-step meaning that when going from `:stopped` to `:playing`
  there are 2 state changes (`:stopped` -> `:prepared` and `:prepared` -> `:playing`) resulting in
  invocation of proper callbacks (such as `c:Membrane.Element.Base.handle_stopped_to_prepared/2`
  or `c:Membrane.Parent.handle_prepared_to_playing/1`)
  """

  @type t :: :stopped | :prepared | :playing | :terminating

  defguard is_playback_state(atom) when atom in [:stopped, :prepared, :playing, :terminating]
end
