defmodule Membrane.Pipeline do
  @moduledoc """
  Module containing functions for constructing and supervising pipelines.
  """

  use Membrane.Mixins.Log
  use GenServer


  @type element_name_t :: String.t
  @type element_def_t :: {module, struct}
  @type element_defs_t :: %{required(element_name_t) => element_def_t}


  @doc """
  Starts the Pipeline based on given module and links it to the current
  process.

  Pipeline options are passed to module's handle_init callback.

  Process options are internally passed to `GenServer.start_link/3`.

  Returns the same values as `GenServer.start_link/3`.
  """
  @spec start_link(module, any, GenServer.options) :: GenServer.on_start
  def start_link(module, pipeline_options, process_options \\ []) do
    debug("Start Link: module = #{inspect(module)}, pipeline_options = #{inspect(pipeline_options)}, process_options = #{inspect(process_options)}")
    GenServer.start_link(__MODULE__, {module, pipeline_options}, process_options)
  end


  @doc """
  Does the same as `start_link/3` but starts process outside of supervision tree.
  """
  @spec start(module, any, GenServer.options) :: GenServer.on_start
  def start(module, pipeline_options, process_options \\ []) do
    debug("Start: module = #{inspect(module)}, pipeline_options = #{inspect(pipeline_options)}, process_options = #{inspect(process_options)}")
    GenServer.start(__MODULE__, {module, pipeline_options}, process_options)
  end


  @doc """
  Callback invoked on process initialization.

  It will receive pipeline options passed to `start_link/4` or `start/4`.

  It is supposed to return `{:ok, initial_elements, initial_state}` or
  `{:error, reason}`.

  Initial elements is a map where key is a string with element name unique
  within the pipeline, and value is a tuple of `{element_module, element_options}`
  that will be used to spawn the element process.
  """
  @callback handle_init(any) ::
    {:ok, element_defs_t, any} |
    {:error, any}



  @doc """
  Sends synchronous call to the given element requesting it to prepare.

  It will wait for reply for amount of time passed as second argument
  (in milliseconds).

  In case of success, returns `:ok`.

  If any of the child elements has failed to reach desired state it returns
  `{:error, reason}`. Please note that in such case state of some elements may
  be already changed.
  """
  @spec prepare(pid, timeout) :: :ok | {:error, any}
  def prepare(server, timeout \\ 5000) when is_pid(server) do
    debug("Prepare -> #{inspect(server)}")
    GenServer.call(server, :membrane_prepare, timeout)
  end


  @doc """
  Sends synchronous call to the given element requesting it to start playing.

  It will wait for reply for amount of time passed as second argument
  (in milliseconds).

  In case of success, returns `:ok`.

  If any of the child elements has failed to reach desired state it returns
  `{:error, reason}`. Please note that in such case state of some elements may
  be already changed.
  """
  @spec play(pid, timeout) :: :ok | {:error, any}
  def play(server, timeout \\ 5000) when is_pid(server) do
    debug("Play -> #{inspect(server)}")
    GenServer.call(server, :membrane_play, timeout)
  end


  @doc """
  Sends synchronous call to the given element requesting it to stop playing.

  It will wait for reply for amount of time passed as second argument
  (in milliseconds).

  In case of success, returns `:ok`.

  If any of the child elements has failed to reach desired state it returns
  `{:error, reason}`. Please note that in such case state of some elements may
  be already changed.
  """
  @spec stop(pid, timeout) :: :ok | {:error, any}
  def stop(server, timeout \\ 5000) when is_pid(server) do
    debug("Stop -> #{inspect(server)}")
    GenServer.call(server, :membrane_stop, timeout)
  end


  # Private API

  @doc false
  def init({module, pipeline_options}) do
    case module.handle_init(pipeline_options) do
      {:ok, initial_elements, internal_state} ->

        case initial_elements |> spawn_elements(%{}) do
          {:ok, elements} ->
            {:ok, %{
              elements: elements,
              internal_state: internal_state,
            }}

          {:error, reason} ->
            warn("Failed to initialize pipeline: reason = #{inspect(reason)}")
            {:stop, reason}
        end

      {:error, reason} ->
        warn("Failed to initialize pipeline: reason = #{inspect(reason)}")
        {:stop, reason}
    end
  end


  @doc false
  def handle_call(:membrane_prepare, _from, %{elements: elements} = state) do
    case elements |> Map.to_list |> call_element(:prepare) do
      :ok ->
        {:reply, :ok, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end


  @doc false
  def handle_call(:membrane_play, _from, %{elements: elements} = state) do
    case elements |> Map.to_list |> call_element(:play) do
      :ok ->
        {:reply, :ok, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end


  @doc false
  def handle_call(:membrane_stop, _from, %{elements: elements} = state) do
    case elements |> Map.to_list |> call_element(:stop) do
      :ok ->
        {:reply, :ok, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end


  defp call_element([], _fun_name), do: :ok

  defp call_element([{_name, pid}|tail], fun_name) do
    case Kernel.apply(Membrane.Element, fun_name, [pid]) do
      :ok ->
        call_element(tail, fun_name)

      :noop ->
        call_element(tail, fun_name)

      {:error, reason} ->
        {:error, reason}
    end
  end


  defp spawn_elements(elements, acc) when is_map(elements) do
    spawn_elements(Map.to_list(elements), acc)
  end

  defp spawn_elements([], acc) do
    {:ok, acc}
  end

  defp spawn_elements([{name, {module, options}}|tail], acc) do
    case Membrane.Element.start_link(module, options) do
      {:ok, pid} ->
        spawn_elements(tail, Map.put(acc, name, pid))

      {:error, reason} ->
        {:error, reason}
    end
  end


  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Membrane.Pipeline

      # Default implementations

      @doc false
      def handle_init(_options) do
        {:ok, %{}, %{}}
      end


      defoverridable [
        handle_init: 1,
      ]
    end
  end
end
