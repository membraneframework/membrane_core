defmodule Membrane.Device.AudioEnumerator do
  @moduledoc """
  Behaviour for defining enumerators of audio devices.
  """

  alias Membrane.Device.AudioDevice


  @doc """
  Returns list of available audio devices.
  """
  @callback list() :: {:ok, [] | [%AudioDevice{}]} | {:error, reason}
  
end
