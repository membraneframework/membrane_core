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

  require Logger

  alias Membrane.{Element, Pad, Sync}
  alias Membrane.Bin.CallbackContext

  alias Membrane.Core.{
    Bin,
    CallbackHandler,
    Child,
    Parent,
    Message
  }

  alias Membrane.Core.Child.{PadController, PadModel, PadSpecHandler, PadsSpecs}
  alias Membrane.Core.Bin.{State, LinkingBuffer}
  alias Membrane.{CallbackError, Element}

  require Element
  require Message
  require Pad
  require PadsSpecs
  require PadModel
  require Membrane.PlaybackState

  @type state_t :: Bin.State.t()

  @type callback_return_t ::
          {:ok | {:ok, [Membrane.Parent.Action.t()]} | {:error, any}, state_t()} | {:error, any}

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
              {{:ok, [Membrane.Parent.Action.spec_action_t()]}, Bin.State.internal_state_t()}
              | {:error, any}

  @doc """
  Callback that is called when new pad has beed added to bin. Executed
  ONLY for dynamic pads.
  """
  @callback handle_pad_added(
              pad :: Pad.ref_t(),
              context :: CallbackContext.PadAdded.t(),
              state :: Bin.State.internal_state_t()
            ) :: callback_return_t

  @doc """
  Callback that is called when some pad of the bin has beed removed. Executed
  ONLY for dynamic pads.
  """
  @callback handle_pad_removed(
              pad :: Pad.ref_t(),
              context :: CallbackContext.PadRemoved.t(),
              state :: Bin.State.internal_state_t()
            ) :: callback_return_t

  @doc """
  Automatically implemented callback used to determine whether bin exports clock.
  """
  @callback membrane_clock? :: boolean()

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
      Logger.debug("""
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
    :ok = Membrane.Core.Logger.put_bin_prefix(name)
    Logger.metadata(log_metadata)

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
    Child.LifecycleController.handle_demand_unit(demand_unit, pad_ref, state)
    |> noreply()
  end

  @impl GenServer
  def handle_info(Message.new(:handle_unlink, pad_ref), state) do
    PadController.handle_pad_removed(pad_ref, state)
    |> noreply()
  end

  @impl GenServer
  def handle_info(message, state) do
    Parent.MessageDispatcher.handle_message(message, state)
  end

  @impl GenServer
  def handle_call(Message.new(:set_controlling_pid, pid), _, state) do
    Child.LifecycleController.handle_controlling_pid(pid, state)
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
    Child.LifecycleController.handle_watcher(watcher, state)
    |> reply()
  end

  @doc """
  Brings all the stuff necessary to implement a pipeline.

  Options:
    - `:bring_spec?` - if true (default) imports and aliases `Membrane.ParentSpec`
    - `:bring_pad?` - if true (default) requires and aliases `Membrane.Pad`
  """
  defmacro __using__(options) do
    quote location: :keep do
      use Membrane.Parent, unquote(options)
      alias unquote(__MODULE__)
      @behaviour unquote(__MODULE__)

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
      def handle_notification(notification, _from, state),
        do: {{:ok, notify: notification}, state}

      @impl true
      def handle_pad_added(_pad, _ctx, state), do: {:ok, state}

      @impl true
      def handle_pad_removed(_pad, _ctx, state), do: {:ok, state}

      defoverridable handle_init: 1,
                     handle_notification: 3,
                     handle_pad_added: 3,
                     handle_pad_removed: 3,
                     membrane_clock?: 0
    end
  end
end
