defmodule Membrane.Integration.ActionsHandlingOrderTest do
  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  defmodule DelayedPlayingPipeline do
    use Membrane.Pipeline

    @impl true
    def handle_setup(_ctx, state) do
      self() |> send(:wake_up_buddy)
      {[setup: :incomplete, start_timer: {:one, Membrane.Time.second()}], state}
    end

    @impl true
    def handle_info(:wake_up_buddy, _ctx, state) do
      {[setup: :complete, timer_interval: {:one, Membrane.Time.seconds(10)}], state}
    end

    @impl true
    def handle_playing(_ctx, state) do
      {[timer_interval: {:one, Membrane.Time.seconds(5)}], state}
    end

    @impl true
    def handle_tick(:one, ctx, state) do
      # IO.inspect(ctx, limit: :infinity)
      IO.puts("TICK")
      {[], state}
    end
  end

  # no to to co trzeba zrobic: dopisz pipeline podobny do powyzszego, ktory w handle info rzuci bufor, i w handle playing rzuci bufor
  # na moje oko to zachowanie powyzej powinno przejsc, tak, ze najpierw bedzie wyslany bufor z playing zamiast z info, ale no
  # to powinno sie wyalac wg mnie.

  # ale to powyzej nie ejst jakies turbo istotne, najpierw zrob tak zeby tick powyzej trwal co 5 sekund
  # i przekmin dlaczego zmiany lukasza cokolwiek naprawily
end
