defmodule Membrane.Pipeline do
  @moduledoc """
  Module containing functions for constructing and supervising pipelines.
  """

  use Membrane.Mixins.Log
  use GenServer
  alias Membrane.Pipeline.{State,Spec}


  # Type that defines possible return values of start/start_link functions.
  @type on_start :: GenServer.on_start

  # Type that defines possible process options passed to start/start_link
  # functions.
  @type process_options_t :: GenServer.options

  # Type that defines possible pipeline-specific options passed to
  # start/start_link functions.
  @type pipeline_options_t :: struct | nil


  # Type that defines a single command that may be returned from handle_*
  # callbacks.
  #
  # If it is `{:forward, {child_name, message}}` it will cause sending
  # given message to the child.
  @type callback_return_command_t ::
    {:forward, {Membrane.Element.name_t, any}}

  # Type that defines list of commands that may be returned from handle_*
  # callbacks.
  @type callback_return_commands_t :: [] | [callback_return_command_t]


  @doc """
  Starts the Pipeline based on given module and links it to the current
  process.

  Pipeline options are passed to module's handle_init callback.

  Process options are internally passed to `GenServer.start_link/3`.

  Returns the same values as `GenServer.start_link/3`.
  """
  @spec start_link(module, pipeline_options_t, process_options_t) :: on_start
  def start_link(module, pipeline_options \\ nil, process_options \\ []) do
    debug("Start Link: module = #{inspect(module)}, pipeline_options = #{inspect(pipeline_options)}, process_options = #{inspect(process_options)}")
    GenServer.start_link(__MODULE__, {module, pipeline_options}, process_options)
  end


  @doc """
  Does the same as `start_link/3` but starts process outside of supervision tree.
  """
  @spec start(module, pipeline_options_t, process_options_t) :: on_start
  def start(module, pipeline_options \\ nil, process_options \\ []) do
    debug("Start: module = #{inspect(module)}, pipeline_options = #{inspect(pipeline_options)}, process_options = #{inspect(process_options)}")
    GenServer.start(__MODULE__, {module, pipeline_options}, process_options)
  end


  @doc """
  Callback invoked on process initialization.

  It will receive pipeline options passed to `start_link/4` or `start/4`.

  It is supposed to return one of:

  * `{:ok, pipeline_topology, initial_state}` - if there are some children,
    but the pipeline has to remain stopped
  * `{:ok, initial_state}` - if there are no children but the pipeline has to
    remain stopped,
  * `{:play, pipeline_topology, initial_state}` - if there are some children,
    and the pipeline has to immediately start playing,
  * `{:error, reason}` - on error.

  See `Membrane.Pipeline.Spec` for more information about how to define
  elements and links in the pipeline.
  """
  @callback handle_init(pipeline_options_t) ::
    {:ok, any} |
    {:ok, Spec.t, any} |
    {:play, Spec.t, any} |
    {:error, any}


  @doc """
  Callback invoked on if any of the child element has sent a message.

  It will receive message, sender name and state.

  It is supposed to return `{:ok, state}`.
  """
  @callback handle_message(Membrane.Message.t, Membrane.Element.name_t, any) ::
    {:ok, any}


  @doc """
  Callback invoked when pipeline is receiving message of other kind. It will
  receive the message and pipeline state.

  If it returns `{:ok, new_state}` it just updates pipeline's state to the new
  state.

  If it returns `{:ok, command_list, new_state}` it executes given commands.

  If it returns `{:error, reason, new_state}` it indicates that something
  went wrong, and pipeline was unable to handle callback. Error along with
  reason will be propagated to the message bus and state will be updated to
  the new state.
  """
  @callback handle_other(any, any) ::
    {:ok, any} |
    {:ok, callback_return_commands_t, any}



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
    GenServer.call(server, :membrane_stop, timeout)
  end


  # Private API

  @doc false
  def init({module, pipeline_options}) do
    case module.handle_init(pipeline_options) do
      {:ok, internal_state} ->
        {:ok, %State{
          internal_state: internal_state,
          module: module,
        }}

      {:ok, %Spec{children: nil}, internal_state} ->
        {:ok, %State{
          internal_state: internal_state,
          module: module,
        }}

      {:ok, spec, internal_state} ->
        case do_init(module, internal_state, spec) do
          {:ok, state} ->
            {:ok, state}

          {:error, reason} ->
            {:stop, {:init, reason}}
        end

      {:play, spec, internal_state} ->
        case do_init(module, internal_state, spec) do
          {:ok, state} ->
            case do_play(state) do
              :ok ->
                {:ok, state}

              {:error, reason} ->
                {:stop, {:play, reason}}
            end

          {:error, reason} ->
            {:stop, {:init, reason}}
        end
    end
  end


  @doc false
  def handle_call(:membrane_prepare, _from, %State{children_to_pids: children_to_pids} = state) do
    debug("Changing playback state of children to PREPARED, state = #{inspect(state)}")
    case children_to_pids |> Map.to_list |> call_element(:prepare) do
      :ok ->
        debug("Changed playback state of children to PREPARED, state = #{inspect(state)}")
        {:reply, :ok, state}

      {:error, reason} ->
        warn("Unable to change playback state of children to PREPARED, reason = #{inspect(reason)}, state = #{inspect(state)}")
        {:reply, {:error, reason}, state}
    end
  end


  @doc false
  def handle_call(:membrane_play, _from, state) do
    case do_play(state) do
      :ok ->
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end


  @doc false
  def handle_call(:membrane_stop, _from, %State{children_to_pids: children_to_pids} = state) do
    debug("Changing playback state of children to STOPPED, state = #{inspect(state)}")
    case children_to_pids |> Map.to_list |> call_element(:stop) do
      :ok ->
        debug("Changed playback state of children to STOPPED, state = #{inspect(state)}")
        {:reply, :ok, state}

      {:error, reason} ->
        warn("Unable to change playback state of children to STOPPED, reason = #{inspect(reason)}, state = #{inspect(state)}")
        {:reply, {:error, reason}, state}
    end
  end


  @doc false
  def handle_info({:membrane_message, %Membrane.Message{} = message}, %State{pids_to_children: pids_to_children, module: module, internal_state: internal_state} = state) do
    # FIXME set sender
    case module.handle_message(message, self(), internal_state) do
      {:ok, new_internal_state} ->
        {:noreply, %{state | internal_state: new_internal_state}}
    end
  end


  @doc false
  # Callback invoked on other incoming message
  def handle_info(message, %State{module: module, internal_state: internal_state} = state) do
    case module.handle_other(message, internal_state)  do
      {:ok, new_internal_state} ->
        {:noreply, %{state | internal_state: new_internal_state}}

      {:ok, commands, new_internal_state} ->
        case handle_commands_recurse(commands, %{state | internal_state: new_internal_state}) do
          {:ok, new_state} ->
            {:noreply, new_state}
        end
    end
  end


  defp handle_commands_recurse([], state), do: {:ok, state}

  defp handle_commands_recurse([{:forward, {element_name, message}} = command|tail], %State{children_to_pids: children_to_pids} = state) do
    case children_to_pids |> Map.get(element_name) do
      nil ->
        raise """
        You have returned invalid pipeline command.

        Your callback has returned command #{inspect(command)} which refers to
        child named #{inspect(element_name)}. There's no such child in this
        pipeline. Known children are:

            #{inspect(children_to_pids |> Map.keys)}

        This is probably a bug in your code.
        """

      pid ->
        send(pid, message)
    end

    handle_commands_recurse(tail, state)
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


  # Links children based on given specification and map for mapping children
  # names into PIDs.
  #
  # On success it returns `:ok`.
  #
  # On error it returns `{:error, {reason, failed_link}}`.
  #
  # Please note that this function is not atomic and in case of error there's
  # a chance that some of children will remain linked.
  defp link_children(links, children_to_pids)
  when is_map(links) and is_map(children_to_pids) do
    debug("Linking children: links = #{inspect(links)}")
    link_children_recurse(links |> Map.to_list, children_to_pids)
  end


  defp link_children_recurse([], _children_to_pids), do: :ok

  defp link_children_recurse([{{from_name, from_pad}, {to_name, to_pad}} = link|rest], children_to_pids) do
    case children_to_pids |> Map.has_key?(from_name) do
      true ->
        case children_to_pids |> Map.has_key?(to_name) do
          true ->
            from_pid = children_to_pids |> Map.get(from_name)
            to_pid = children_to_pids |> Map.get(to_name)

            case Membrane.Element.link({from_pid, from_pad}, {to_pid, to_pad}) do
              :ok ->
                link_children_recurse(rest, children_to_pids)

              {:error, reason} ->
                {:error, {reason, link}}
            end

          false ->
            {:error, {:unknown_to, link}}
        end

      false ->
        {:error, {:unknown_from, link}}
    end
  end


  # Sets message bus for children.
  #
  # On success it returns `:ok`.
  #
  # On error it returns `{:error, reason}`.
  #
  # Please note that this function is not atomic and in case of error there's
  # a chance that some of children will have the message bus set.
  # Links children based on given specification and map for mapping children
  # names into PIDs.
  #
  # On success it returns `:ok`.
  #
  # On error it returns `{:error, {reason, failed_link}}`.
  #
  # Please note that this function is not atomic and in case of error there's
  # a chance that some of children will remain linked.
  defp set_children_message_bus(children_to_pids)
  when is_map(children_to_pids) do
    debug("Setting message bus of children: children_to_pids = #{inspect(children_to_pids)}")
    set_children_message_bus_recurse(children_to_pids |> Map.values)
  end


  defp set_children_message_bus_recurse([]), do: :ok

  defp set_children_message_bus_recurse([child_pid|rest]) do
    case Membrane.Element.set_message_bus(child_pid, self()) do
      :ok ->
        set_children_message_bus_recurse(rest)

      {:error, reason} ->
        {:error, {reason, child_pid}}
    end
  end


  # Starts children based on given specification and links them to the current
  # process in the supervision tree.
  #
  # On success it returns `{:ok, {names_to_pids, pids_to_names}}` where two
  # values returned are maps that allow to easily map child names to process PIDs
  # in both ways.
  #
  # On error it returns `{:error, reason}`.
  #
  # Please note that this function is not atomic and in case of error there's
  # a chance that some of children will remain running.
  defp start_children(children) when is_map(children) do
    debug("Starting children: children = #{inspect(children)}")
    start_children_recurse(children |> Map.to_list, {%{}, %{}})
  end


  # Recursion that starts children processes, final case
  defp start_children_recurse([], acc), do: {:ok, acc}

  # Recursion that starts children processes, case when both module and options
  # are provided.
  defp start_children_recurse([{name, {module, options}}|tail], {names_to_pids, pids_to_names}) do
    case Membrane.Element.start_link(module, options) do
      {:ok, pid} ->
        start_children_recurse(tail, {
          names_to_pids |> Map.put(name, pid),
          pids_to_names |> Map.put(pid, name),
        })

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Recursion that starts children processes, case when only module is provided
  defp start_children_recurse([{name, module}|tail], {names_to_pids, pids_to_names}) do
    debug("Starting child: name = #{inspect(name)}, module = #{inspect(module)}")
    case Membrane.Element.start_link(module) do
      {:ok, pid} ->
        start_children_recurse(tail, {
          names_to_pids |> Map.put(name, pid),
          pids_to_names |> Map.put(pid, name),
        })

      {:error, reason} ->
        {:error, reason}
    end
  end


  defp do_init(module, internal_state, %Spec{children: children, links: links} = spec) do
    debug("Initializing: spec = #{inspect(spec)}, internal_state = #{inspect(internal_state)}")
    case children |> start_children do
      {:ok, {children_to_pids, pids_to_children}} ->
        case links |> link_children(children_to_pids) do
          :ok ->
            case children_to_pids |> set_children_message_bus do
              :ok ->
                debug("Initialized: spec = #{inspect(spec)}, internal_state = #{inspect(internal_state)}, children_to_pids = #{inspect(children_to_pids)}")
                {:ok, %State{
                  children_to_pids: children_to_pids,
                  pids_to_children: pids_to_children,
                  internal_state: internal_state,
                  module: module,
                }}

              {:error, reason} ->
                warn("Failed to initialize pipeline: unable to set message bus for pipeline's children, reason = #{inspect(reason)}")
                {:error, reason}
            end

          {:error, {reason, failed_link}} ->
            warn("Failed to initialize pipeline: unable to link pipeline's children, reason = #{inspect(reason)}, failed_link = #{inspect(failed_link)}")
            {:error, reason}
        end

      {:error, reason} ->
        warn("Failed to initialize pipeline: unable to start pipeline's children, reason = #{inspect(reason)}")
        {:error, reason}
    end
  end


  defp do_play(%State{children_to_pids: children_to_pids} = state) do
    debug("Changing playback state of children to PLAYING, state = #{inspect(state)}")
    case children_to_pids |> Map.to_list |> call_element(:play) do
      :ok ->
        debug("Changed playback state of children to PLAYING, state = #{inspect(state)}")
        :ok

      {:error, reason} ->
        warn("Unable to change playback state of children to PLAYING, reason = #{inspect(reason)}, state = #{inspect(state)}")
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


      @doc false
      def handle_other(_message, state) do
        {:ok, state}
      end


      defoverridable [
        handle_init: 1,
        handle_message: 3,
        handle_other: 2,
      ]
    end
  end
end
