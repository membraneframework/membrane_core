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
    {:error, any}


  @doc """
  Performs diff on two given list of audio devices.

  It will return a tuple that will contain three elements:

  * list of added audio devices,
  * list of removed audio devices,
  * list of unchanged audio devices.

  While comparing it take under consideration whole `Membrane.Device.AudioDevice`
  struct. In other words, changing any of the fields will cause this function
  to detect change.

  Please note that at the moment this function can have suboptimal computational
  complexity. It should not be an issue as usually list of devices is short
  but you are warned.
  """
  @spec diff_list([] | [%AudioDevice{}], [] | [%AudioDevice{}]) ::
    {[] | [%AudioDevice{}], [] | [%AudioDevice{}], [] | [%AudioDevice{}]}
  def diff_list(list1, list2) do
    mapset1 = list1 |> MapSet.new
    mapset2 = list2 |> MapSet.new

    # FIXME we are creating mapset only to call difference and intersection
    # Looking at their source code they seem to be rather straightforward
    # functions with not that good complexity. Can't we replace this with
    # something better?
    added     = MapSet.difference(mapset2, mapset1) |> MapSet.to_list
    removed   = MapSet.difference(mapset1, mapset2) |> MapSet.to_list
    unchanged = MapSet.intersection(mapset2, mapset1) |> MapSet.to_list

    {added, removed, unchanged}
  end


  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Membrane.Device.AudioEnumerator
    end
  end
end
