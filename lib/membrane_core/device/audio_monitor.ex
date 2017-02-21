defmodule Membrane.Device.AudioMonitor do
  @moduledoc """
  Worker process for monitoring list of available audio endpoints.

  Example:

      defmodule MyApp.MyDeviceMonitor do
        use Membrane.Device.AudioMonitor

        def handle_diff(added, removed, unchanged, state) do
          IO.puts "Audio endpoints added: " <> inspect(added)
          IO.puts "Audio endpoints removed: " <> inspect(removed)

          {:ok, state}
        end
      end

      {:ok, pid} = Membrane.Device.AudioMonitor.start_link(MyApp.MyDeviceMonitor,
        [Membrane.Device.WASAPI.Enumerator])
  """


  alias Membrane.Device.AudioEndpoint
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

  * list of added audio endpoints,
  * list of removed audio endpoints,
  * list of unchanged audio endpoints,
  * state.

  It is supposed to return `{:ok, new_state}`.
  """
  @callback handle_diff([] | [%AudioEndpoint{}], [] | [%AudioEndpoint{}], [] | [%AudioEndpoint{}], any) ::
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


  @doc """
  Synchronously calls given server and retreives currently known list of active
  endpoints.

  Query may be one of `:all`, `:capture` or `:playback`, and it can be used to
  limit scope of returned endpoints.

  It will return endpoints known by the process, which were retreived during last
  refresh.

  It will wait for reply for timeout passed, expressed in milliseconds.

  Returns list of `AudioEndpoint` structs.
  """
  @spec get_endpoints(pid, :all | :capture | :playback, timeout) :: [] | [%AudioEndpoint{}]
  def get_endpoints(server, query \\ :all, timeout \\ 5000) do
    Connection.call(server, {:get_endpoints, query}, timeout)
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
          endpoints: [],
          internal_state: internal_state,
        }}

      {:error, reason} ->
        {:stop, reason}
    end
  end


  @doc false
  def connect(:init, %{module: module, enumerators: enumerators, interval: interval, internal_state: internal_state} = state) do
    case list_endpoints(enumerators, []) do
      [] ->
        {:backoff, interval, %{state | endpoints: []}}

      endpoints ->
        case module.handle_diff(endpoints, [], [], internal_state) do
          {:ok, new_internal_state} ->
            {:backoff, interval, %{state | endpoints: endpoints, internal_state: new_internal_state}}
        end
    end
  end


  @doc false
  def connect(_, %{module: module, enumerators: enumerators, interval: interval, endpoints: endpoints, internal_state: internal_state} = state) do
    current_endpoints = list_endpoints(enumerators, [])

    {added, removed, unchanged} =
      AudioEnumerator.diff_list(endpoints, current_endpoints)

    cond do
      added != [] || removed != [] ->
        case module.handle_diff(added, removed, unchanged, internal_state) do
          {:ok, new_internal_state} ->
            {:backoff, interval, %{state | endpoints: current_endpoints, internal_state: new_internal_state}}
        end

      true ->
        {:backoff, interval, state}
    end
  end


  @doc false
  def handle_call({:get_endpoints, :all}, _from, %{endpoints: endpoints} = state) do
    {:reply, endpoints, state}
  end


  @doc false
  def handle_call({:get_endpoints, query}, _from, %{endpoints: endpoints} = state) do
    filtered_endpoints =
      endpoints
      |> Enum.filter(fn(%AudioEndpoint{direction: direction}) ->
        direction == query
      end)

    {:reply, filtered_endpoints, state}
  end


  defp list_endpoints([], acc), do: acc
  defp list_endpoints([enumerator_head|tail], acc) do
    {:ok, endpoints} = enumerator_head.list(:all)
    list_endpoints(tail, acc ++ endpoints)
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


      @doc false
      def handle_diff(_added, _removed, _unchagned, state) do
        {:ok, state}
      end


      defoverridable [
        handle_init: 2,
        handle_diff: 4,
      ]
    end
  end
end
