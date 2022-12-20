defmodule Membrane.Playback do
  @moduledoc """
  Playback defines whether media is processed within a pipeline (`:playing`) or not (`:stopped`).
  """
  @type t :: :stopped | :playing
end
