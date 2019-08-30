defmodule Membrane.Core.ElementTest do
  use ExUnit.Case, async: true

  defmodule SomeElement do
    use Membrane.Element.Base.Source
    def_output_pad :output, caps: :any

    @impl true
    def handle_other(msg, _ctx, state) do
      {{:ok, notify: msg}, state}
    end
  end

  alias __MODULE__.SomeElement
  alias Membrane.Element
  alias Membrane.Core.Message

  require Membrane.Core.Message

  describe "Not linked element" do
    test "should shutdown when pipeline is down" do
      task =
        Task.async(fn ->
          receive do: (:exit -> :ok)
        end)

      {:ok, elem_pid} = Element.start(task.pid, SomeElement, :name, %{}, [])
      :ok = Element.set_watcher(elem_pid, self())
      ref = Process.monitor(elem_pid)
      send(task.pid, :exit)
      Task.await(task)
      assert_receive {:DOWN, ^ref, :process, ^elem_pid, :normal}
    end

    test "should not assume pipeline is down when getting any monitor message" do
      task =
        Task.async(fn ->
          receive do: (:exit -> :ok)
        end)

      on_exit(fn -> send(task.pid, :exit) end)

      {:ok, elem_pid} = Element.start(task.pid, SomeElement, :name, %{}, [])
      :ok = Element.set_watcher(elem_pid, self())
      ref = make_ref()
      self = self()
      send(elem_pid, {:DOWN, ref, :process, self, :normal})

      assert_receive Message.new(:notification, [
                       :name,
                       {:DOWN, ^ref, :process, ^self, :normal}
                     ])

      assert Process.alive?(elem_pid)
    end
  end
end
