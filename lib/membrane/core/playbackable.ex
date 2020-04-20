defprotocol Membrane.Core.Playbackable do
  @moduledoc false

  # Protocol that has to be adopted by modules that use `Membrane.Core.Playback`.
  #
  # Modules that adopt `Membrane.Core.PlaybackHandler` behaviour have to store their
  # playback state and controlling pid. `Membrane.Core.Playbackable` is used as
  # an abstraction that allows to access those values.

  alias Membrane.Core.Playback

  @spec get_playback(__MODULE__.t()) :: Playback.t()
  def get_playback(playbackable)

  @spec set_playback(__MODULE__.t(), Playback.t()) :: __MODULE__.t()
  def set_playback(playbackable, playback)

  @spec update_playback(__MODULE__.t(), (Playback.t() -> Playback.t())) :: __MODULE__.t()
  def update_playback(playbackable, playback)

  @spec get_and_update_playback(__MODULE__.t(), (Playback.t() -> {ret, Playback.t()})) ::
          {ret, __MODULE__.t()}
        when ret: Playback.t() | any
  def get_and_update_playback(playbackable, update_f)

  @spec get_controlling_pid(__MODULE__.t()) :: pid | nil
  def get_controlling_pid(playbackable)
end

defmodule Membrane.Core.Playbackable.Default do
  @moduledoc false

  # The default implementation for `Membrane.Core.Playbackable`.
  # Assumes that `playbackable` is a map and stores `playback` and
  # `controlling_pid` inside it.

  defmacro __using__(_) do
    quote location: :keep do
      def get_playback(%{playback: playback}), do: playback

      def set_playback(playbackable, playback), do: %{playbackable | playback: playback}

      def update_playback(playbackable, f), do: playbackable |> Map.update!(:playback, f)

      def get_and_update_playback(playbackable, f),
        do: playbackable |> Map.get_and_update!(:playback, f)

      def get_controlling_pid(playbackable), do: nil

      defoverridable get_playback: 1,
                     set_playback: 2,
                     update_playback: 2,
                     get_and_update_playback: 2,
                     get_controlling_pid: 1
    end
  end
end

defimpl Membrane.Core.Playbackable, for: Any do
  use Membrane.Core.Playbackable.Default
end
