defmodule Membrane.Pipeline do
  @moduledoc """
  Module containing functions for constructing and supervising pipelines.
  """

  use Membrane.Mixins.Log, tags: :core
  use Membrane.Mixins.CallbackHandler
  use Membrane.Mixins.Playback
  use GenServer
  alias Membrane.Pipeline.{State,Spec}
  alias Membrane.Element
  use Membrane.Helper
  import Helper.GenServer

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
  def start_link(module, pipeline_options \\ nil, process_options \\ []), do:
    do_start(:start_link, module, pipeline_options, process_options)


  @doc """
  Does the same as `start_link/3` but starts process outside of supervision tree.
  """
  @spec start(module, pipeline_options_t, process_options_t) :: on_start
  def start(module, pipeline_options \\ nil, process_options \\ []), do:
    do_start(:start, module, pipeline_options, process_options)


  defp do_start(method, module, pipeline_options, process_options) do
    with :ok <- (if module |> is_pipeline? do :ok else :not_pipeline end)
    do
      debug """
        Pipeline start link: module: #{inspect module},
        pipeline options: #{inspect pipeline_options},
        process options: #{inspect process_options}
        """
      apply GenServer, method, [__MODULE__, {module, pipeline_options}, process_options]
    else
      :not_pipeline -> warn_error """
        Cannot start pipeline, passed module #{inspect module} is not a Membrane Pipeline.
        Make sure that given module is the right one and it uses Membrane.Pipeline
        """, {:not_pipeline, module}
    end
  end


  @callback is_membrane_pipeline :: true

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
    {:play, Spec.t, any}


  @doc """
  Callback invoked on if any of the child Element has sent a message.

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


  # Private API

  @doc false
  def init(module) when is_atom module do
    init {module, module |> Module.concat(Options) |> Helper.Module.struct}
  end

  @doc false
  def init({module, pipeline_options}) do
    with \
      [init: {{:ok, spec}, internal_state}] <- [init: module.handle_init(pipeline_options)],
      state = %State{internal_state: internal_state, module: module}
    do
      send self(), [:membrane_pipeline_spec, spec]
      {:ok, state}
    else
      [init: {:error, reason}] -> warn_error """
        Pipeline handle_init callback returned an error
        """, reason
        {:stop, {:pipeline_init, reason}}
      [init: other] ->
        reason = {:handle_init_invalid_return, other}
        warn_error """
        Pipeline's handle_init replies are expected to be {:ok, {spec, state}}
        but got #{inspect(other)}.

        This is probably a bug in your pipeline's code, check return value
        of #{module}.handle_init/1.
        """, reason
        {:stop, {:pipeline_init, reason}}
      {:error, reason} ->
        warn_error "Error during pipeline initialization", reason
        {:stop, {:pipeline_init, reason}}
    end
  end

  def is_pipeline?(module) do
    module |> Helper.Module.check_behaviour(:is_membrane_pipeline)
  end

  defp handle_spec(%Spec{children: children, links: links}, state) do
    debug """
      Initializing pipeline spec
      children: #{inspect children}
      links: #{inspect links}
      """
    with \
      {:ok, children} <- children |> parse_children,
      #TODO: add dedup_children veryfying that there are no duplicate children
      {children, state} = children |> resolve_children(state),
      {:ok, {children_to_pids, pids_to_children}} <- children |> start_children,
      state = %State{state |
          pids_to_children: Map.merge(state.pids_to_children, pids_to_children),
          children_to_pids: Map.merge(state.children_to_pids, children_to_pids),
        },
      {:ok, links} <- links |> parse_links,
      {{:ok, links}, state} <- links |> resolve_links(state),
      :ok <- links |> link_children(state),
      {children_names, children_pids} = children_to_pids |> Enum.unzip,
      :ok <- children_pids |> set_children_message_bus,
      {:ok, state} <- exec_and_handle_callback(:handle_spec_started, [children_names], state)
      #:ok <- children_pids
        #|> Helper.Enum.each_with(&Element.change_playback_state &1, state.playback_state)
    do
      debug """
        Initializied pipeline spec
        children: #{inspect children}
        children pids: #{inspect children_to_pids}
        links: #{inspect links}
        """
      {{:ok, children_names}, state}
    else
      {:error, reason} ->
        warn_error "Failed to initialize pipeline spec", {:cannot_handle_spec, reason}
    end
  end

  defp parse_children(children) when is_map(children), do:
    children |> Helper.Enum.map_with(&parse_child/1)

  defp parse_child({name, {module, options, params}})
  when is_atom(name) and is_atom(module) and is_list(params)
  do {:ok, %{name: name, module: module, options: options, params: params}}
  end
  defp parse_child({name, {module, options}}), do:
    parse_child({name, {module, options, []}})
  defp parse_child({name, module}), do:
    parse_child({name, {module, module |> Module.concat(Options) |> Helper.Module.struct}})
  defp parse_child(config), do:
    {:error, invalid_child_config: config}

  defp resolve_children(children, state), do:
    children |> Enum.map_reduce(state, &resolve_child/2)

  defp resolve_child(%{name: name, params: params} = child, state) do
    cond do
      params |> Keyword.get(:indexed) ->
        {id, state} = state |> State.get_increase_child_id(name)
        {%{child | name: {name, id}}, state}
      true -> {child, state}
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
  defp start_children(children) do
    debug("Starting children: #{inspect children}")
    with {:ok, result} <- children |> Helper.Enum.map_with(&start_child/1)
    do
      {names, pids} = result |> Enum.unzip
      {:ok, {names |> Map.new, pids |> Map.new}}
    end
  end

  # Recursion that starts children processes, case when both module and options
  # are provided.
  defp start_child(%{name: name, module: module, options: options}) do
    debug "Pipeline: starting child: name: #{inspect name}, module: #{inspect module}"
    with {:ok, pid} <- Element.start_link(module, name, options),
         :ok <- Element.set_controlling_pid(pid, self())
    do {:ok, {{name, pid}, {pid, name}}}
    else
      {:error, reason} ->
        warn_error "Cannot start child #{inspect name}", {:cannot_start_child, name, reason}
    end
  end

  defp parse_links(links), do: links |> Helper.Enum.map_with(&parse_link/1)

  defp parse_link(link) do
    with \
      {:ok, link} <- link ~> (
          {{from, from_pad}, {to, to_pad, params}} ->
            {:ok, %{from: %{element: from, pad: from_pad}, to: %{element: to, pad: to_pad}, params: params}}
          {{from, from_pad}, {to, to_pad}} ->
            {:ok, %{from: %{element: from, pad: from_pad}, to: %{element: to, pad: to_pad}, params: []}}
          _ -> {:error, :invalid_link}
        ),
      :ok <- [link.from.pad, link.to.pad] |> Helper.Enum.each_with(&parse_pad/1)
      do {:ok, link}
      else {:error, reason} -> {:error, {:invalid_link, link, reason}}
      end
  end

  defp parse_pad(name)
  when is_atom name or is_binary name do :ok end
  defp parse_pad(pad), do: {:error, {:invalid_pad_format, pad}}


  defp resolve_links(links, state) do
    links |> Helper.Enum.map_reduce_with(state, fn %{from: from, to: to} = link, st ->
      with \
        {{:ok, from}, st} <- from |> resolve_link(st),
        {{:ok, to}, st} <- to |> resolve_link(st),
        do: {{:ok, %{link | from: from, to: to}}, st}
      end)
  end

  defp resolve_link(%{element: element, pad: pad_name} = elementpad, state)
  do
    element = cond do
      state |> State.is_dynamic?(element) ->
        {:ok, last_id} = state |> State.get_last_child_id(element)
        {element, last_id}
      true -> element
    end
    with \
      {:ok, pid} <- state |> State.get_child(element),
      {:ok, pad_name} <- pid |> GenServer.call({:membrane_get_pad_full_name, [pad_name]})
    do
      {{:ok, %{element: element, pad: pad_name}}, state}
    else
      {:error, reason} -> {:error, {:resolve_link, elementpad, reason}}
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
  defp link_children(links, state) do
    debug("Linking children: links = #{inspect(links)}")
    with \
      :ok <- links |> Helper.Enum.each_with(& do_link_children &1, state),
      :ok <- state.pids_to_children
        |> Helper.Enum.each_with(fn {pid, _} -> pid |> Element.handle_linking_finished end),
      do: :ok
  end

  defp do_link_children(%{from: from, to: to, params: params} = link, state) do
    with \
      {:ok, from_pid} <- state |> State.get_child(from.element),
      {:ok, to_pid} <- state |> State.get_child(to.element),
      :ok <- Element.link(from_pid, to_pid, from.pad, to.pad, params)
    do :ok
    else {:error, reason} -> {:error, {:cannot_link, link, reason}}
    end
  end

  defp set_children_message_bus(elements_pids) do
    with :ok <- elements_pids |> Helper.Enum.each_with(fn pid ->
        pid |> Element.set_message_bus(self())
      end)
    do :ok
    else {:error, reason} -> {:error, {:cannot_set_message_bus, reason}}
    end
  end



  @doc false
  def handle_playback_state(old, new, %State{pids_to_children: pids_to_children} = state) do
    children = pids_to_children |> Map.keys

    children |> Enum.each(fn child ->
      Element.change_playback_state(child, new)
    end)

    pending_pids = children |> Enum.chunk(1) |> Enum.into(%{}, fn [pid] -> {pid, true} end)
    {:ok, %{state | pending_pids: pending_pids, async_state_change: true}}
  end


  # todo validate messages
  @doc false
  def handle_info({:membrane_playback_state_changed, pid, playback_state}, %{target_playback_state: target_playback_state, playback_state: current_state, pending_pids: pending_pids} = state) do
    {_, new_pending_pids} = pending_pids |> Map.pop(pid)
    new_state = %{state | pending_pids: new_pending_pids}

    if new_pending_pids == %{} do

      #FIXME handle_callback
      ## exec and handle callback
      #{callback, args} = (case {old, new} do
        #{_, :prepared} -> {:handle_prepare, [old]}
        #{:prepared, :playing} -> {:handle_play, []}
        #{:prepared, :stopped} -> {:handle_stop, []}
      #end)

      #{:ok, state} <- exec_and_handle_callback(callback, args, state)

      continue_playback_change(new_state) |> noreply(nil)
    else
      {:ok, %{state | pending_pids: new_pending_pids}} |> noreply(nil)
    end
  end


  #FIXME this should be part of playback mixin
  def handle_info({:membrane_change_playback_state, new_state}, state) do
        import Membrane.Helper.GenServer
        IO.puts "changing pipeline state to #{new_state}"
        do_change_playback_state(new_state, state) |> noreply(state)
      end

  @doc false
  def handle_info([:membrane_pipeline_spec, spec], state) do
    with {{:ok, _children}, state} <- spec |> handle_spec(state)
    do {:ok, state}
    end |> noreply(state)
  end

  @doc false
  def handle_info([:membrane_message, from, %Membrane.Message{} = message], state) do
    with {:ok, _} <- state |> State.get_child(from)
    do exec_and_handle_callback(:handle_message, [message, from], state)
    end |> noreply(state)
  end

  def handle_action({:forward, {elementname, message}}, _cb, _params, state) do
    with {:ok, pid} <- state |> State.get_child(elementname)
    do
      send pid, message
      {:ok, state}
    else {:error, reason} ->
      {:error, {:cannot_forward_message, [element: elementname, message: message], reason}}
    end
  end

  def handle_action({:spec, spec = %Spec{}}, _cb, _params, state) do
    with {{:ok, _children}, state} <- handle_spec(spec, state),
    do: {:ok, state}
  end

  def handle_action({:remove_child, children}, _cb, _params, state) do
    with {{:ok, pids}, state} <- children
        |> Helper.listify
        |> Helper.Enum.map_reduce_with(state, fn c, st -> State.pop_child st, c end),
      :ok <- pids |> Helper.Enum.each_with(&Element.stop/1),
      :ok <- pids |> Helper.Enum.each_with(&Element.unlink/1),
      :ok <- pids |> Helper.Enum.each_with(&Element.shutdown/1)
    do {:ok, state}
    else {:error, reason} -> {:error, {:cannot_remove_children, children, reason}}
    end
  end

  def handle_action(action, callback, params, state) do
    available_actions = [
        "{:forward, {elementname, message}}",
        "{:spec, spec}",
        "{:remove_child, children}"
      ]
    handle_invalid_action(action, callback, params, available_actions, __MODULE__, state)
  end

  defmacro __using__(_) do
    quote location: :keep do
      alias Membrane.Pipeline
      @behaviour Membrane.Pipeline

      @doc """
      Enables to check whether module is membrane pipeline
      """
      def is_membrane_pipeline, do: true

      # Default implementations

      @doc false
      def handle_init(_options), do: {:ok, %{}}

      @doc false
      def handle_prepare(_playback_state, state), do: {:ok, state}

      @doc false
      def handle_play(state), do: {:ok, state}

      @doc false
      def handle_stop(state), do: {:ok, state}

      @doc false
      def handle_message(_message, _from, state), do: {:ok, state}

      @doc false
      def handle_other(_message, state), do: {:ok, state}

      @doc false
      def handle_spec_started(_new_children, state), do: {:ok, state}


      defoverridable [
        handle_init: 1,
        handle_prepare: 2,
        handle_play: 1,
        handle_stop: 1,
        handle_message: 3,
        handle_other: 2,
        handle_spec_started: 2,
      ]
    end
  end
end
