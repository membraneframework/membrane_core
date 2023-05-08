defmodule Membrane.Playback do
  @moduledoc """
  Playback defines whether media is processed within a pipeline (`:playing`) or not (`:stopped`).

  Component playback will not enter `:playing` state until its parent playback is playing and
  all components from the `spec`, that started this component have ended their setups and linked
  their pads.

  By default, component setup ends with the end of `handle_setup/2` callback.
  If `{:setup, :incomplete}` is returned there, setup lasts until `{:setup, :complete}`
  is returned from antoher callback.

  Untils the setup lasts, the component won't enter `:playing` playback.
  """

  @typedoc @moduledoc
  @type t :: :stopped | :playing
end
