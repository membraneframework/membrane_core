defmodule Membrane.Bin do
  @moduledoc """
  Bins, similarly to pipelines, are containers for elements.
  However, at the same time, they can be placed and linked within pipelines.
  Although bin is a separate Membrane entity, it can be perceived as a pipeline within an element.
  Bins can also be nested within one another.

  There are two main reasons why bins are useful:
  * they enable creating reusable element groups
  * they allow managing their children, for instance by dynamically spawning or replacing them as the stream changes.

  In order to create bin `use Membrane.Bin` in your callback module.
  """

  use Bunch
  use GenServer

  import Membrane.Helper.GenServer

  require Membrane.Core.Message
  require Membrane.Logger

  alias Membrane.{CallbackError, Child, Core, Pad, Sync}
  alias Membrane.Bin.CallbackContext
  alias Membrane.Core.{CallbackHandler, Message}
  alias Membrane.Core.Bin.{LinkingBuffer, State}
  alias Membrane.Core.Child.{PadController, PadSpecHandler, PadsSpecs}
  alias Membrane.Helper.LocationPath

  @type state_t :: map | struct

  @type callback_return_t ::
          {:ok | {:ok, [Membrane.Parent.Action.t()]} | {:error, any}, state_t}
          | {:error, any}

  @typedoc """
  Defines options that can be passed to `start_link/3` and received
  in `c:handle_init/1` callback.
  """
  @type options_t :: struct | nil

  @typedoc """
  Type that defines a bin name by which it is identified.
  """
  @type name_t :: any()

  @doc """
  Enables to check whether module is membrane bin.
  """
  @callback membrane_bin? :: true

  @doc """
  Callback invoked on initialization of bin process. It should parse options
  and initialize bin's internal state. Internally it is invoked inside
  `c:GenServer.init/1` callback.
  """
  @callback handle_init(options :: options_t) ::
              {{:ok, [Membrane.Parent.Action.spec_action_t()]}, any}
              | {:error, any}

  @doc """
  Callback that is called when new pad has beed added to bin. Executed
  ONLY for dynamic pads.
  """
  @callback handle_pad_added(
              pad :: Pad.ref_t(),
              context :: CallbackContext.PadAdded.t(),
              state :: any
            ) :: callback_return_t

  @doc """
  Callback that is called when some pad of the bin has beed removed. Executed
  ONLY for dynamic pads.
  """
  @callback handle_pad_removed(
              pad :: Pad.ref_t(),
              context :: CallbackContext.PadRemoved.t(),
              state :: any
            ) :: callback_return_t

  @doc """
  Automatically implemented callback used to determine whether bin exports clock.
  """
  @callback membrane_clock? :: boolean()

  @doc """
  Callback invoked when bin transition from `:stopped` to `:prepared` state has finished,
  that is all of its children are prepared to enter `:playing` state.
  """
  @callback handle_stopped_to_prepared(
              context :: CallbackContext.PlaybackChange.t(),
              state :: any
            ) ::
              callback_return_t

  @doc """
  Callback invoked when bin transition from `:playing` to `:prepared` state has finished,
  that is all of its children are prepared to be stopped.
  """
  @callback handle_playing_to_prepared(
              context :: CallbackContext.PlaybackChange.t(),
              state :: any
            ) ::
              callback_return_t

  @doc """
  Callback invoked when bin is in `:playing` state, i.e. all its children
  are in this state.
  """
  @callback handle_prepared_to_playing(
              context :: CallbackContext.PlaybackChange.t(),
              state :: any
            ) ::
              callback_return_t

  @doc """
  Callback invoked when bin is in `:playing` state, i.e. all its children
  are in this state.
  """
  @callback handle_prepared_to_stopped(
              context :: CallbackContext.PlaybackChange.t(),
              state :: any
            ) ::
              callback_return_t

  @doc """
  Callback invoked when bin is in `:terminating` state, i.e. all its children
  are in this state.
  """
  @callback handle_stopped_to_terminating(
              context :: CallbackContext.PlaybackChange.t(),
              state :: any
            ) :: callback_return_t

  @doc """
  Callback invoked when a notification comes in from an element.
  """
  @callback handle_notification(
              notification :: Membrane.Notification.t(),
              element :: Child.name_t(),
              context :: CallbackContext.Notification.t(),
              state :: any
            ) :: callback_return_t

  @doc """
  Callback invoked when bin receives a message that is not recognized
  as an internal membrane message.

  Useful for receiving ticks from timer, data sent from NIFs or other stuff.
  """
  @callback handle_other(
              message :: any,
              context :: CallbackContext.Other.t(),
              state :: any
            ) ::
              callback_return_t

  @doc """
  Callback invoked when an element receives `Membrane.Event.StartOfStream` event.
  """
  @callback handle_element_start_of_stream(
              {Child.name_t(), Pad.ref_t()},
              context :: CallbackContext.StreamManagement.t(),
              state :: any
            ) :: callback_return_t

  @doc """
  Callback invoked when an element receives `Membrane.Event.EndOfStream` event.
  """
  @callback handle_element_end_of_stream(
              {Child.name_t(), Pad.ref_t()},
              context :: CallbackContext.StreamManagement.t(),
              state :: any
            ) :: callback_return_t

  @doc """
  Callback invoked when `Membrane.ParentSpec` is linked and in the same playback
  state as bin.

  This callback can be started from `c:handle_init/1` callback or as
  `t:Membrane.Core.Parent.Action.spec_action_t/0` action.
  """
  @callback handle_spec_started(
              children :: [Child.name_t()],
              context :: CallbackContext.SpecStarted.t(),
              state :: any
            ) :: callback_return_t

  @doc PadsSpecs.def_pad_docs(:input, :bin)
  defmacro def_input_pad(name, spec) do
    PadsSpecs.def_bin_pad(name, :input, spec)
  end

  @doc PadsSpecs.def_pad_docs(:output, :bin)
  defmacro def_output_pad(name, spec) do
    PadsSpecs.def_bin_pad(name, :output, spec)
  end

  @doc """
  Defines that bin exposes a clock which is a proxy to one of its children.

  If this macro is not called, no ticks will be forwarded to parent, regardless
  of clock definitions in its children.
  """
  defmacro def_clock(doc \\ "") do
    quote do
      @membrane_bin_exposes_clock true

      Module.put_attribute(__MODULE__, :membrane_clock_moduledoc, """
      ## Clock

      This bin exposes a clock of one of its children.

      #{unquote(doc)}
      """)

      @impl true
      def membrane_clock?, do: true
    end
  end

  @doc """
  Starts the Bin based on given module and links it to the current
  process.

  Bin options are passed to module's `c:handle_init/1` callback.

  Process options are internally passed to `GenServer.start_link/3`.

  Returns the same values as `GenServer.start_link/3`.
  """
  @spec start_link(
          atom,
          module,
          bin_options :: options_t,
          process_options :: GenServer.options()
        ) :: GenServer.on_start()
  def start_link(name, module, bin_options \\ nil, log_metadata, process_options \\ []) do
    if module |> bin? do
      Membrane.Logger.debug("""
      Bin start link: module: #{inspect(module)},
      bin options: #{inspect(bin_options)},
      process options: #{inspect(process_options)}
      """)

      GenServer.start_link(__MODULE__, {name, module, bin_options, log_metadata}, process_options)
    else
      raise """
      Cannot start bin, passed module #{inspect(module)} is not a Membrane Bin.
      Make sure that given module is the right one and it uses Membrane.Bin
      """
    end
  end

  @doc """
  Changes bin's playback state to `:stopped` and terminates its process
  """
  @spec stop_and_terminate(bin :: pid) :: :ok
  def stop_and_terminate(bin) do
    Message.send(bin, :stop_and_terminate)
    :ok
  end

  @impl GenServer
  def init({name, module, bin_options, log_metadata}) do
    name_str = if String.valid?(name), do: name, else: inspect(name)
    :ok = Membrane.Logger.set_prefix(name_str <> " bin")
    Logger.metadata(log_metadata)

    :ok = LocationPath.set_current_path(log_metadata[:parent_path])
    :ok = LocationPath.append_current_path(name_str <> " bin")

    clock =
      if module |> Bunch.Module.check_behaviour(:membrane_clock?) do
        {:ok, pid} = Membrane.Clock.start_link(proxy: true)
        pid
      end

    state =
      %State{
        bin_options: bin_options,
        module: module,
        name: name,
        clock_proxy: clock,
        synchronization: %{
          parent_clock: clock,
          timers: %{},
          clock: clock,
          # This is a sync for siblings. This is not yet allowed.
          stream_sync: Sync.no_sync(),
          latency: 0
        },
        children_log_metadata: log_metadata
      }
      |> PadSpecHandler.init_pads()

    with {:ok, state} <-
           CallbackHandler.exec_and_handle_callback(
             :handle_init,
             Membrane.Core.Bin.ActionHandler,
             %{state: false},
             [bin_options],
             state
           ) do
      {:ok, state}
    else
      {{:error, reason}, _state} ->
        raise CallbackError, kind: :error, callback: {module, :handle_init}, reason: reason

      {other, _state} ->
        raise CallbackError, kind: :bad_return, callback: {module, :handle_init}, value: other
    end
  end

  @doc """
  Checks whether module is a bin.
  """
  @spec bin?(module) :: boolean
  def bin?(module) do
    module |> Bunch.Module.check_behaviour(:membrane_bin?)
  end

  @impl GenServer
  # Bin-specific message.
  # This forwards all :demand, :caps, :buffer, :event
  # messages to an appropriate element.
  def handle_info(Message.new(type, _args, for_pad: pad) = msg, state)
      when type in [:demand, :caps, :buffer, :event, :push_mode_announcment] do
    outgoing_pad =
      pad
      |> Pad.get_corresponding_bin_pad()

    LinkingBuffer.store_or_send(msg, outgoing_pad, state)
    ~> {:ok, &1}
    |> noreply()
  end

  @impl GenServer
  # Element-specific message.
  def handle_info(Message.new(:demand_unit, [demand_unit, pad_ref]), state) do
    Core.Child.LifecycleController.handle_demand_unit(demand_unit, pad_ref, state)
    |> noreply()
  end

  @impl GenServer
  def handle_info(Message.new(:handle_unlink, pad_ref), state) do
    PadController.handle_pad_removed(pad_ref, state)
    |> noreply()
  end

  @impl GenServer
  def handle_info(message, state) do
    Core.Parent.MessageDispatcher.handle_message(message, state)
  end

  @impl GenServer
  def handle_call(Message.new(:set_controlling_pid, pid), _, state) do
    Core.Child.LifecycleController.handle_controlling_pid(pid, state)
    |> reply()
  end

  @impl GenServer
  def handle_call(
        Message.new(:handle_link, [pad_ref, pad_direction, pid, other_ref, other_info, props]),
        _from,
        state
      ) do
    {{:ok, info}, state} =
      PadController.handle_link(pad_ref, pad_direction, pid, other_ref, other_info, props, state)

    {{:ok, info}, state}
    |> reply()
  end

  @impl GenServer
  def handle_call(Message.new(:linking_finished), _, state) do
    PadController.handle_linking_finished(state)
    |> reply()
  end

  @impl GenServer
  def handle_call(Message.new(:handle_watcher, watcher), _, state) do
    Core.Child.LifecycleController.handle_watcher(watcher, state)
    |> reply()
  end

  @doc """
  Brings all the stuff necessary to implement a bin.

  Options:
    - `:bring_spec?` - if true (default) imports and aliases `Membrane.ParentSpec`
    - `:bring_pad?` - if true (default) requires and aliases `Membrane.Pad`
  """
  defmacro __using__(options) do
    bring_spec =
      if options |> Keyword.get(:bring_spec?, true) do
        quote do
          import Membrane.ParentSpec
          alias Membrane.ParentSpec
        end
      end

    bring_pad =
      if options |> Keyword.get(:bring_pad?, true) do
        quote do
          require Membrane.Pad
          alias Membrane.Pad
        end
      end

    quote location: :keep do
      alias unquote(__MODULE__)
      @behaviour unquote(__MODULE__)

      unquote(bring_spec)
      unquote(bring_pad)

      import Membrane.Element.Base, only: [def_options: 1]

      import unquote(__MODULE__),
        only: [def_input_pad: 2, def_output_pad: 2, def_clock: 0, def_clock: 1]

      require Membrane.Core.Child.PadsSpecs

      Membrane.Core.Child.PadsSpecs.ensure_default_membrane_pads()

      @impl true
      def membrane_bin?, do: true

      @impl true
      def membrane_clock?, do: false

      @impl true
      def handle_init(_options), do: {{:ok, spec: %Membrane.ParentSpec{}}, %{}}

      @impl true
      def handle_pad_added(_pad, _ctx, state), do: {:ok, state}

      @impl true
      def handle_pad_removed(_pad, _ctx, state), do: {:ok, state}

      @impl true
      def handle_stopped_to_prepared(_ctx, state), do: handle_stopped_to_prepared(state)

      @impl true
      def handle_prepared_to_playing(_ctx, state), do: handle_prepared_to_playing(state)

      @impl true
      def handle_playing_to_prepared(_ctx, state), do: handle_playing_to_prepared(state)

      @impl true
      def handle_prepared_to_stopped(_ctx, state), do: handle_prepared_to_stopped(state)

      @impl true
      def handle_stopped_to_terminating(_ctx, state), do: handle_stopped_to_terminating(state)

      @impl true
      def handle_other(message, _ctx, state), do: handle_other(message, state)

      @impl true
      def handle_spec_started(new_children, _ctx, state),
        do: handle_spec_started(new_children, state)

      @impl true
      def handle_element_start_of_stream({element, pad}, _ctx, state),
        do: handle_element_start_of_stream({element, pad}, state)

      @impl true
      def handle_element_end_of_stream({element, pad}, _ctx, state),
        do: handle_element_end_of_stream({element, pad}, state)

      @impl true
      def handle_notification(notification, element, _ctx, state),
        do: handle_notification(notification, element, state)

      # DEPRECATED:

      @doc false
      def handle_stopped_to_prepared(state), do: {:ok, state}
      @doc false
      def handle_prepared_to_playing(state), do: {:ok, state}
      @doc false
      def handle_playing_to_prepared(state), do: {:ok, state}
      @doc false
      def handle_prepared_to_stopped(state), do: {:ok, state}
      @doc false
      def handle_stopped_to_terminating(state), do: {:ok, state}
      @doc false
      def handle_other(_message, state), do: {:ok, state}
      @doc false
      def handle_spec_started(_new_children, state), do: {:ok, state}
      @doc false
      def handle_element_start_of_stream({_element, _pad}, state), do: {:ok, state}
      @doc false
      def handle_element_end_of_stream({_element, _pad}, state), do: {:ok, state}
      @doc false
      def handle_notification(notification, _element, state),
        do: {{:ok, notify: notification}, state}

      deprecated = [
        handle_stopped_to_prepared: 1,
        handle_prepared_to_playing: 1,
        handle_playing_to_prepared: 1,
        handle_prepared_to_stopped: 1,
        handle_stopped_to_terminating: 1,
        handle_other: 2,
        handle_spec_started: 2,
        handle_element_start_of_stream: 2,
        handle_element_end_of_stream: 2,
        handle_notification: 3
      ]

      defoverridable [
                       membrane_clock?: 0,
                       handle_init: 1,
                       handle_pad_added: 3,
                       handle_pad_removed: 3,
                       handle_stopped_to_prepared: 2,
                       handle_playing_to_prepared: 2,
                       handle_prepared_to_playing: 2,
                       handle_prepared_to_stopped: 2,
                       handle_stopped_to_terminating: 2,
                       handle_other: 3,
                       handle_spec_started: 3,
                       handle_element_start_of_stream: 3,
                       handle_element_end_of_stream: 3,
                       handle_notification: 4
                     ] ++ deprecated
    end
  end
end
