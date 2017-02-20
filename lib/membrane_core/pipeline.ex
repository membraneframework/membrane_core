defmodule Membrane.Pipeline do
  @moduledoc """
  Module containing functions for constructing and supervising pipelines.
  """

  use Membrane.Mixins.Log
  use GenServer
  alias Membrane.PipelineState
  alias Membrane.PipelineTopology

  # Type that defines possible return values of start/start_link functions.
  @type on_start :: GenServer.on_start

  # Type that defines possible process options passed to start/start_link
  # functions.
  @type process_options_t :: GenServer.options

  # Type that defines possible pipeline-specific options passed to
  # start/start_link functions.
  @type pipeline_options_t :: struct | nil



  @doc """
  Starts the Pipeline based on given module and links it to the current
  process.

  Pipeline options are passed to module's handle_init callback.

  Process options are internally passed to `GenServer.start_link/3`.

  Returns the same values as `GenServer.start_link/3`.
  """
  @spec start_link(module, pipeline_options_t, process_options_t) :: on_start
  def start_link(module, pipeline_options, process_options \\ []) do
    debug("Start Link: module = #{inspect(module)}, pipeline_options = #{inspect(pipeline_options)}, process_options = #{inspect(process_options)}")
    GenServer.start_link(__MODULE__, {module, pipeline_options}, process_options)
  end


  @doc """
  Does the same as `start_link/3` but starts process outside of supervision tree.
  """
  @spec start(module, pipeline_options_t, process_options_t) :: on_start
  def start(module, pipeline_options, process_options \\ []) do
    debug("Start: module = #{inspect(module)}, pipeline_options = #{inspect(pipeline_options)}, process_options = #{inspect(process_options)}")
    GenServer.start(__MODULE__, {module, pipeline_options}, process_options)
  end


  @doc """
  Callback invoked on process initialization.

  It will receive pipeline options passed to `start_link/4` or `start/4`.

  It is supposed to return `{:ok, pipeline_topology, initial_state}`,
  `{:ok, initial_state}` or `{:error, reason}`.

  See `Membrane.PipelineTopology` for more information about how to define
  elements and links in the pipeline.
  """
  @callback handle_init(pipeline_options_t) ::
    {:ok, any} |
    {:ok, PipelineTopology.t, any} |
    {:error, any}


  @doc """
  Callback invoked on if any of the child element has sent a message.

  It will receive message, sender name and state.

  It is supposed to return `{:ok, state}`.
  """
  @callback handle_message(Membrane.Message.t, Membrane.Element.name_t, any) ::
    {:ok, any}



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
      {:ok, internal_state} ->
        {:ok, %PipelineState{
          internal_state: internal_state,
          module: module,
        }}

      {:ok, %PipelineTopology{children: nil}, internal_state} ->
        {:ok, %PipelineState{
          internal_state: internal_state,
          module: module,
        }}

      {:ok, %PipelineTopology{children: children}, internal_state} ->
        case children |> PipelineTopology.start_children do
          {:ok, {elements_to_pids, pids_to_elements}} ->
            {:ok, %PipelineState{
              elements_to_pids: elements_to_pids,
              pids_to_elements: pids_to_elements,
              internal_state: internal_state,
              module: module,
            }}

          {:error, reason} ->
            warn("Failed to initialize pipeline: unable to start pipeline's children, reason = #{inspect(reason)}")
            {:stop, reason}
        end

      {:error, reason} ->
        warn("Failed to initialize pipeline: handle_init has failed, reason = #{inspect(reason)}")
        {:stop, reason}
    end
  end


  @doc false
  def handle_call(:membrane_prepare, _from, %PipelineState{elements_to_pids: elements_to_pids} = state) do
    case elements_to_pids |> Map.to_list |> call_element(:prepare) do
      :ok ->
        {:reply, :ok, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end


  @doc false
  def handle_call(:membrane_play, _from, %PipelineState{elements_to_pids: elements_to_pids} = state) do
    case elements_to_pids |> Map.to_list |> call_element(:play) do
      :ok ->
        {:reply, :ok, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end


  @doc false
  def handle_call(:membrane_stop, _from, %PipelineState{elements_to_pids: elements_to_pids} = state) do
    case elements_to_pids |> Map.to_list |> call_element(:stop) do
      :ok ->
        {:reply, :ok, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end


  @doc false
  def handle_info({:membrane_message, %Membrane.Message{} = message}, from, %PipelineState{pids_to_elements: pids_to_elements, module: module, internal_state: internal_state} = state) do
    case module.handle_message(message, Map.get(pids_to_elements, from), internal_state) do
      {:ok, new_internal_state} ->
        {:noreply, %{state | internal_state: new_internal_state}}
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



  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Membrane.Pipeline

      # Default implementations

      @doc false
      def handle_init(_options) do
        {:ok, %{}}
      end


      @doc false
      def handle_message(_message, _from, state) do
        {:ok, state}
      end


      defoverridable [
        handle_init: 1,
        handle_message: 3,
      ]
    end
  end
end
