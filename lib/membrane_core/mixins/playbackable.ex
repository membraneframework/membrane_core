defprotocol Membrane.Mixins.Playbackable do
  alias Membrane.Mixins.Playback

  @spec get_playback(__MODULE__.t) :: Playback.t
  def get_playback(playbackable)

  @spec set_playback(__MODULE__.t, Playback.t) :: __MODULE__.t
  def set_playback(playbackable, playback)

  @spec update_playback(__MODULE__.t, (Playback.t -> Playback.t)) :: __MODULE__.t
  def update_playback(playbackable, playback)

  @spec get_and_update_playback(__MODULE__.t, (Playback.t -> Playback.t)) :: {Playback.t, __MODULE__.t}
  def get_and_update_playback(playbackable, update_f)

  @spec get_controlling_pid(__MODULE__.t) :: pid | nil
  def get_controlling_pid(playbackable)

end

defmodule Membrane.Mixins.Playbackable.Default do
  defmacro __using__ _ do
    quote location: :keep do
      def get_playback(%{playback: playback}), do: playback

      def set_playback(playbackable, playback), do: %{playbackable | playback: playback}

      def update_playback(playbackable, f), do:
        playbackable |> set_playback(playbackable |> get_playback |> f.())

      def get_and_update_playback(playbackable, update_f) do
        playback = playbackable |> get_playback
        {playback, playbackable |> set_playback(playback |> update_f.())}
      end

      def get_controlling_pid(playbackable), do: nil

      defoverridable [
        get_playback: 1,
        set_playback: 2,
        update_playback: 2,
        get_and_update_playback: 2,
        get_controlling_pid: 1,
      ]
    end
  end
end

defimpl Membrane.Mixins.Playbackable, for: Any do
  use Membrane.Mixins.Playbackable.Default
end
