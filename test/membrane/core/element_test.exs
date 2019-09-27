defmodule Membrane.Core.ElementTest do
  use ExUnit.Case, async: true

  defmodule SomeElement do
    use Membrane.Source
    def_output_pad :output, caps: :any

    @impl true
    def handle_other(msg, _ctx, state) do
      {{:ok, notify: msg}, state}
    end
  end

  alias __MODULE__.SomeElement
  alias Membrane.Core.Element
  alias Membrane.Core.Message

  require Membrane.Core.Message

  describe "Not linked element" do
    test "should shutdown when pipeline is down" do
      monitored_proc = spawn(fn -> receive do: (:exit -> :ok) end)

      {:ok, elem_pid} =
        monitored_proc
        |> element_init_options
        |> Element.start()

      {:ok, _clock} = Message.call(elem_pid, :handle_watcher, self())
      ref = Process.monitor(elem_pid)
      send(monitored_proc, :exit)
      assert_receive {:DOWN, ^ref, :process, ^elem_pid, :normal}
    end

    test "should not assume pipeline is down when getting any monitor message" do
      monitored_proc = spawn(fn -> receive do: (:exit -> :ok) end)
      on_exit(fn -> send(monitored_proc, :exit) end)

      {:ok, elem_pid} =
        monitored_proc
        |> element_init_options
        |> Element.start()

      {:ok, _clock} = Message.call(elem_pid, :handle_watcher, self())
      ref = make_ref()
      deceased_pid = self()
      send(elem_pid, {:DOWN, ref, :process, deceased_pid, :normal})

      assert_receive Message.new(:notification, [
                       :name,
                       {:DOWN, ^ref, :process, ^deceased_pid, :normal}
                     ])

      assert Process.alive?(elem_pid)
    end
  end

  defp element_init_options(pipeline) do
    %{
      module: SomeElement,
      name: :name,
      user_options: %{},
      parent: pipeline,
      clock: nil,
      sync: Membrane.Sync.no_sync()
    }
  end
end
