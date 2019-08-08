defmodule Membrane.PlaybackState do
  @moduledoc """
  Defines possible playback states.

   - `:stopped` - Idle. No resources should be initialized nor allocated.
   - `:prepared` - Ready for processing data. All necessary resources should be allocated and initialized.
   - `:playing` - Data is being processed.
  """
  @type t :: :stopped | :prepared | :playing

  defguard is_playback_state(atom) when atom in [:stopped, :prepared, :playing]
end
