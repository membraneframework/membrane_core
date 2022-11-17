defmodule Membrane.Testing.MockResourceGuard do
  @moduledoc """
  Mock for `Membrane.ResourceGuard`.

  Informs the test process about registered cleanup functions and tags.
  Works with `Membrane.Testing.Assertions`, for example
  `Membrane.Testing.Assertions.assert_resource_guard_register/4`:

      iex> guard = #{inspect(__MODULE__)}.start_link_supervised!()
      ...> Membrane.ResourceGuard.register(guard, fn -> :abc end, tag: :some_tag)
      ...> import Membrane.Testing.Assertions
      ...> assert_resource_guard_register(guard, function, :some_tag)
      ...> function.()
      :abc

  """
  use GenServer

  require Membrane.Core.Message, as: Message

  @type options :: [test_process: pid]

  @spec child_spec(test_process: pid()) :: Supervisor.child_spec()
  def child_spec(options) do
    super(options) |> Map.merge(%{restart: :transient, id: {__MODULE__, make_ref()}})
  end

  @spec start_link(options) :: {:ok, pid}
  def start_link(options \\ []) do
    options = Keyword.put_new(options, :test_process, self())
    GenServer.start_link(__MODULE__, options)
  end

  @spec start_link_supervised!(options) :: pid
  def start_link_supervised!(options \\ []) do
    options = Keyword.put_new(options, :test_process, self())
    {:ok, pid} = ex_unit_start_supervised({__MODULE__, options})
    pid
  end

  @impl true
  def init(options) do
    {:ok, Map.new(options)}
  end

  @impl true
  def handle_info(Message.new(:register, [function, options]), state) do
    tag = Keyword.fetch!(options, :tag)
    send_to_test_process(state, :register, {function, tag})
    {:noreply, state}
  end

  @impl true
  def handle_info(Message.new(:unregister, tag), state) do
    send_to_test_process(state, :unregister, tag)
    {:noreply, state}
  end

  @impl true
  def handle_info(Message.new(:cleanup, tag), state) do
    send_to_test_process(state, :cleanup, tag)
    {:noreply, state}
  end

  defp ex_unit_start_supervised(child_spec) do
    # It's not a 'normal' call to keep dialyzer quiet
    apply(ExUnit.Callbacks, :start_supervised, [child_spec])
  end

  defp send_to_test_process(%{test_process: test_process}, type, args) do
    send(test_process, {__MODULE__, self(), {type, args}})
  end
end
