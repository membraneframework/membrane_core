defmodule Membrane.Device.AudioMonitor do
  @moduledoc """
  Worker process for monitoring list of available audio devices.

  Example:

      defmodule MyApp.MyDeviceMonitor do
        use Membrane.Device.AudioMonitor

        def handle_diff(added, removed, unchanged, state) do
          IO.puts "Audio devices added: " <> inspect(added)
          IO.puts "Audio devices removed: " <> inspect(removed)

          {:ok, state}
        end
      end

      {:ok, pid} = Membrane.Device.AudioMonitor.start_link(MyApp.MyDeviceMonitor,
        [Membrane.Device.WASAPI.Enumerator])
  """


  alias Membrane.Device.AudioDevice
  alias Membrane.Device.AudioEnumerator


  @doc """
  Callback invoked on process initialization.

  It will receive second and third argument passed to `start_link/4` or `start/4`
  (list of enumerators and interval).

  It is supposed to return `{:ok, initial_state}` or `{:error, reason}`.
  """
  @callback handle_init([module], pos_integer) ::
    {:ok, any} |
    {:error, any}


  @doc """
  Callback invoked when there happens any change to the available interface list.

  It will receive four arguments:

  * list of added audio devices,
  * list of removed audio devices,
  * list of unchanged audio devices,
  * state.

  It is supposed to return `{:ok, new_state}`.
  """
  @callback handle_diff([] | [%AudioDevice{}], [] | [%AudioDevice{}], [] | [%AudioDevice{}], any) ::
    {:ok, any}


  @doc """
  Starts an AudioMonitor process linked to the current process.

  This function accepts four arguments:

  * module to start,
  * list of modules that will be used to query interface lists,
    they have to match `Membrane.Device.AudioEnumerator` behaviour,
  * interval (in milliseconds) of performing a query,
  * additional process options.

  It behaves similarily to `GenServer.start_link/3` and returns the same
  values.
  """
  @spec start_link(module, [module], pos_integer, GenServer.options) :: GenServer.on_start
  def start_link(module, enumerators, interval \\ 5000, process_options \\ []) do
    Connection.start_link(__MODULE__, {module, enumerators, interval}, process_options)
  end


  @doc """
  The same as `start_link/4` but starts the process outside supervision tree.
  """
  @spec start(module, [module], pos_integer, GenServer.options) :: GenServer.on_start
  def start(module, enumerators, interval \\ 5000, process_options \\ []) do
    Connection.start(__MODULE__, {module, enumerators, interval}, process_options)
  end


  @doc """
  Stops given process.

  It waits for given timeout until stop is done.

  It behaves similarily to `GenServer.stop/3` and returns the same values.
  """
  @spec stop(pid, timeout) :: :ok
  def stop(server, timeout \\ 5000) do
    GenServer.stop(server, :normal, timeout)
    :ok
  end


  # Private API

  @doc false
  def init({module, enumerators, interval}) do
    case module.handle_init(enumerators, interval) do
      {:ok, internal_state} ->
        {:connect, :init, %{
          enumerators: enumerators,
          interval: interval,
          module: module,
          previous_devices: nil,
          internal_state: internal_state,
        }}

      {:error, reason} ->
        {:stop, reason}
    end
  end


  def connect(:init, %{module: module, enumerators: enumerators, interval: interval, internal_state: internal_state} = state) do
    case list_devices(enumerators, []) do
      [] ->
        {:backoff, interval, %{state | previous_devices: devices}}

      devices ->
        case module.handle_diff(devices, [], [], internal_state) do
          {:ok, new_internal_state} ->
            {:backoff, interval, %{state | previous_devices: devices, internal_state: new_internal_state}}
        end
    end
  end


  def connect(_, %{module: module, enumerators: enumerators, interval: interval, previous_devices: previous_devices, internal_state: internal_state} = state) do
    current_devices = list_devices(enumerators, [])

    {added, removed, unchanged} =
      AudioEnumerator.diff_list(previous_devices, current_devices)

    cond do
      added != [] || removed != [] ->
        case module.handle_diff(added, removed, unchanged, internal_state) do
          {:ok, new_internal_state} ->
            {:backoff, interval, %{state | previous_devices: current_devices, internal_state: new_internal_state}}
        end

      true ->
        {:backoff, interval, state}
    end
  end


  defp list_devices([], acc), do: acc
  defp list_devices([enumerator_head|tail], acc) do
    {:ok, devices} = enumerator_head.list(:all)
    list_devices(tail, [devices|acc])
  end


  defmacro __using__(_) do
    quote location: :keep do
      use Connection

      @behaviour Membrane.Device.AudioMonitor


      # Default implementations

      @doc false
      def handle_init(_enumerators, _interval) do
        {:ok, %{}}
      end


      defoverridable [
        handle_init: 2,
      ]
    end
  end
end
