defmodule Membrane.Logger do
  @moduledoc """
  Module containing functions spawning, shutting down, and handling messages
  sent to logger.
  """

  alias Membrane.Logger.State


  # Type that defines possible return values of start/start_link functions.
  @type on_start :: GenServer.on_start

  # Type that defines possible process options passed to start/start_link
  # functions.
  @type process_options_t :: GenServer.options

  # Type that defines possible logger-specific options passed to
  # start/start_link functions.
  @type logger_options_t :: struct | nil



  @doc """
  Starts process for logger of given module, initialized with given options and
  links it to the current process in the supervision tree.

  Works similarily to `GenServer.start_link/3` and has the same return values.
  """
  @spec start_link(module, logger_options_t, process_options_t) :: on_start
  def start_link(module, logger_options \\ nil, process_options \\ []) do
    GenServer.start_link(__MODULE__, {module, logger_options}, [name: :logger])
  end


  @doc """
  Starts process for logger of given module, initialized with given options
  outside of the supervision tree.

  Works similarily to `GenServer.start/3` and has the same return values.
  """
  @spec start(module, logger_options_t, process_options_t) :: on_start
  def start(module, logger_options \\ nil, process_options \\ []) do
    GenServer.start(__MODULE__, {module, logger_options}, process_options)
  end


  @doc """
  Stops given logger process.

  It will wait for reply for amount of time passed as second argument
  (in milliseconds).

  Will trigger calling `handle_shutdown/2` logger callback.

  Returns `:ok`.
  """
  @spec shutdown(pid, timeout) :: :ok
  def shutdown(server, timeout \\ 5000) do
    GenServer.stop(server, :normal, timeout)
    :ok
  end



  # Private API

  @doc false
  def init({module, options}) do
    # Call logger's initialization callback
    case module.handle_init(options) do
      {:ok, internal_state} ->
        state = State.new(module, internal_state)
        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end


  @doc false
  def terminate(_reason, %State{module: module, internal_state: internal_state}) do
    # TODO send last message to the logger
    module.handle_shutdown(internal_state)
  end




  # Callback invoked on incoming buffer.
  #
  # It will delegate actual processing to handle_log/5.
  @doc false
  def handle_info({:membrane_log, level, content, timestamp, tags}, %State{module: module, internal_state: internal_state} = state) do
    module.handle_log(level, content, timestamp, tags, internal_state)
      |> handle_callback(state)
      |> format_callback_response(:noreply)
  end


  defp format_callback_response({:ok, new_state}, :reply) do
    {:reply, :ok, new_state}
  end

  defp format_callback_response({:ok, new_state}, :noreply) do
    {:noreply, new_state}
  end

  defp format_callback_response({:error, reason, new_state}, :reply) do
    {:reply, {:error, reason}, new_state}
  end

  defp format_callback_response({:error, _reason, new_state}, :noreply) do
    {:noreply, new_state}
  end


  # Generic handler that can be used to convert return value from
  # logger callback to reply that is accepted by GenServer.handle_*.
  #
  # Case when callback returned successfully and requests no further action.
  defp handle_callback({:ok, new_internal_state}, state) do
    {:ok, %{state | internal_state: new_internal_state}}
  end


  # Generic handler that can be used to convert return value from
  # logger callback to reply that is accepted by GenServer.handle_info.
  #
  # Case when callback returned failure.
  defp handle_callback({:error, reason, new_internal_state}, %{module: module} = state) do
    content = ["Error occurred while trying to log message. Reason = ", inspect(reason)]
    case module.handle_log(:warn, content, Membrane.Time.native_monotonic_time, [], new_internal_state) do
      {:ok, new_internal_state} ->
        {:ok, %{state | internal_state: new_internal_state}}
      {:error, reason, new_internal_state} ->
        {:error, reason, %{state | internal_state: new_internal_state}}
      _ ->
        # raise error
        handle_callback(nil, nil)
    end
  end


  # Error handler for unknown callback return values.
  defp handle_callback(other, _state) do
    raise """
    Logger callback replies are expected to be one of:

        {:ok, state}
        {:error, reason, state}

    for example:

        {:ok, %{key: "val"}}

    but got callback reply #{inspect(other)}.

    This is probably a bug in the logger, check if its callbacks return values
    in the right format.
    """
  end
end
