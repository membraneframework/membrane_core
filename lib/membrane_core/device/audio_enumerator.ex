defmodule Membrane.Device.AudioEnumerator do
  @moduledoc """
  Behaviour for defining enumerators of audio devices.
  """

  alias Membrane.Device.AudioDevice


  @doc """
  Returns list of available audio devices.
  """
  @callback list(:capture | :playback | :all) ::
    {:ok, [] | [%AudioDevice{}]} |
    {:error, reason}


  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Membrane.Device.AudioEnumerator
    end
  end
end
