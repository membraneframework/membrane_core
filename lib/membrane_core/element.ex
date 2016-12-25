defmodule Membrane.Element do
  @moduledoc """
  This module contains functions that can be applied to all elements.
  """

  use Membrane.Mixins.Log


  # Type that defines what may be sent from one element to another.
  @type sendable_t :: %Membrane.Buffer{} | %Membrane.Event{}

  # Type that defines a single command that may be returned from handle_*
  # callbacks.
  #
  # If it is `{:send, pad_name, [buffers_or_events]}` it will cause sending
  # given buffers and/or events downstream to the linked elements via pad of
  # given name.
  @type callback_return_command_t ::
    {:send, Membrane.Pad.name_t, [sendable_t]}

  # Type that defines list of commands that may be returned from handle_*
  # callbacks.
  @type callback_return_commands_t :: [] | [callback_return_command_t]



  @doc """
  Starts process for element of given module, initialized with given options and
  links it to the current process in the supervision tree.

  Works similarily to `GenServer.start_link/3` and has the same return values.
  """
  @spec start_link(module, struct, GenServer.options) :: GenServer.on_start
  def start_link(module, element_options, process_options \\ []) do
    debug("Start Link: module = #{inspect(module)}, element_options = #{inspect(element_options)}, process_options = #{inspect(process_options)}")
    GenServer.start_link(module, element_options, process_options)
  end


  @doc """
  Starts process for element of given module, initialized with given
  element_options outside of the supervision tree.

  Works similarily to `GenServer.start/3` and has the same return values.
  """
  @spec start(module, struct, GenServer.options) :: GenServer.on_start
  def start(module, element_options, process_options \\ []) do
    debug("Start: module = #{inspect(module)}, element_options = #{inspect(element_options)}, process_options = #{inspect(process_options)}")
    GenServer.start(module, element_options, process_options)
  end


  @doc """
  Stops given element process.

  It will wait for reply for amount of time passed as second argument
  (in milliseconds).

  Will trigger calling `handle_shutdown/2` element callback.

  Returns `:ok`.
  """
  @spec shutdown(pid, timeout) :: :ok
  def shutdown(server, timeout \\ 5000) do
    debug("Shutdown -> #{inspect(server)}")
    GenServer.stop(server, :normal, timeout)
    :ok
  end


  @doc """
  Determines module for given process identifier.

  It returns `{:ok, module}` in case of success.

  It returns `{:error, :invalid}` if given pid does not denote element.
  """
  @spec get_module(pid) :: {:ok, module} | {:error, any}
  def get_module(server) when is_pid(server) do
    {:dictionary, items} = :erlang.process_info(server, :dictionary)

    case items |> List.keyfind(:membrane_element_module, 0) do
      nil ->
        # Seems that given pid is not an element
        {:error, :invalid}

      {_key, module} ->
        {:ok, module}
    end
  end


  @doc """
  The same as `get_module/1` but throws error in case of failure.
  """
  @spec get_module!(pid) :: module
  def get_module!(server) when is_pid(server) do
    case get_module(server) do
      {:ok, module} ->
        module
      {:error, reason} ->
        throw reason
    end
  end


  @doc """
  Returns `true` if given module can act as a source element, `false` otherwise.
  """
  @spec is_source?(module) :: boolean
  def is_source?(module) do
    # FIXME use module attributes instead of checking if function is defined
    module.__info__(:functions)
      |> List.keyfind(:potential_source_pads, 0) != nil
  end


  @doc """
  Returns `true` if given module can act as a sink element, `false` otherwise.
  """
  @spec is_sink?(module) :: boolean
  def is_sink?(module) do
    # FIXME use module attributes instead of checking if function is defined
    module.__info__(:functions)
      |> List.keyfind(:potential_sink_pads, 0) != nil
  end


  @doc """
  Sends synchronous call to the given element requesting it to prepare.

  It will wait for reply for amount of time passed as second argument
  (in milliseconds).

  In case of success, returns `:ok`.

  If element is already playing, returns `:noop`.
  """
  @spec prepare(pid, timeout) :: :ok | :noop
  def prepare(server, timeout \\ 5000) when is_pid(server) do
    debug("Prepare -> #{inspect(server)}")
    GenServer.call(server, :membrane_prepare, timeout)
  end


  @doc """
  Sends synchronous call to the given element requesting it to start playing.

  It will wait for reply for amount of time passed as second argument
  (in milliseconds).

  In case of success, returns `:ok`.

  If element is already playing, returns `:noop`.
  """
  @spec play(pid, timeout) :: :ok | :noop
  def play(server, timeout \\ 5000) when is_pid(server) do
    debug("Play -> #{inspect(server)}")
    GenServer.call(server, :membrane_play, timeout)
  end


  @doc """
  Sends synchronous call to the given element requesting it to stop playing.

  It will wait for reply for amount of time passed as second argument
  (in milliseconds).

  In case of success, returns `:ok`.

  If element is not playing, returns `:noop`.
  """
  @spec stop(pid, timeout) :: :ok | :noop
  def stop(server, timeout \\ 5000) when is_pid(server) do
    debug("Stop -> #{inspect(server)}")
    GenServer.call(server, :membrane_stop, timeout)
  end


  @doc """
  Sends synchronous call to the given element requesting it to add given
  element to the list of destinations for buffers that are sent from the
  element.

  It will wait for reply for amount of time passed as second argument
  (in milliseconds).

  In case of success, returns `:ok`.

  If destination is already present, returns `:noop`.

  In case of any of server and destination are the same element,
  returns `{:error, :loop}`.

  In case of any of server or destination is not a pid of an element,
  returns `{:error, :invalid_element}`.

  In case of server is not a source element, returns
  `{:error, :invalid_direction}`.

  In case of destination is not a sink element, returns
  `{:error, {:invalid_direction, pid}}`.
  """
  @spec link({pid, Membrane.Pad.name_t}, {pid, Membrane.Pad.name_t}, timeout) ::
    :ok |
    :noop |
    {:error, :invalid_element} |
    {:error, :invalid_direction} |
    {:error, :loop}
  def link(server, destination, timeout \\ 5000)


  def link({server, server_pad}, {destination, destination_pad}, _timeout)
  when is_pid(server) and is_pid(destination) and server == destination do
    warn("Failed to link #{inspect(server)}/#{inspect(server_pad)} -> #{inspect(destination)}/#{inspect(destination_pad)}: Link source and target are the same")
    {:error, :loop}
  end


  def link({server, server_pad}, {destination, destination_pad}, timeout)
  when is_pid(server) and is_pid(destination) do
    debug("Linking #{inspect(server)}/#{inspect(server_pad)} -> #{inspect(destination)}/#{inspect(destination_pad)}")

    case get_module(server) do
      {:ok, server_module} ->
        case get_module(destination) do
          {:ok, destination_module} ->
            cond do
              is_source?(server_module) && is_sink?(destination_module) ->
                # TODO check if pads are present
                # TODO check if pads match at all
                # TODO check if pads are not already linked
                # FIXME send membrane_link with particular pad combination
                GenServer.call(server, {:membrane_link, destination}, timeout)

              !is_source?(server_module) ->
                warn("Failed to link #{inspect(server)}/#{inspect(server_pad)} -> #{inspect(destination)}/#{inspect(destination_pad)}: #{inspect(server)} (#{server_module}) is not a source element")
                {:error, :invalid_direction}

              !is_sink?(destination_module) ->
                warn("Failed to link #{inspect(server)}/#{inspect(server_pad)} -> #{inspect(destination)}/#{inspect(destination_pad)}: #{inspect(destination)} (#{destination_module}) is not a sink element")
                {:error, :invalid_direction}
            end

          {:error, :invalid} ->
            warn("Failed to link #{inspect(server)}/#{inspect(server_pad)} -> #{inspect(destination)}/#{inspect(destination_pad)}: #{inspect(destination)} is not a PID of an element")
            {:error, :invalid_element}
        end

      {:error, :invalid} ->
        warn("Failed to link #{inspect(server)}/#{inspect(server_pad)} -> #{inspect(destination)}/#{inspect(destination_pad)}: #{inspect(server)} is not a PID of an element")
        {:error, :invalid_element}
    end
  end
end
