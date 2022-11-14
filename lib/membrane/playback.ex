defmodule Membrane.Playback do
  @moduledoc """
  Playback defines whether media is processed within a pipeline (`:playing`) or not (`:stopped`).

  Playback can be controlled with `t:Membrane.Pipeline.Action.playback_t/0`.
  """
  @type t :: :stopped | :playing
end
