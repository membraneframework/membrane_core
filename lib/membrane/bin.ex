defmodule Membrane.Bin do
  use Bunch
  use Membrane.Log, tags: :core
  use GenServer
  use Membrane.Core.PlaybackHandler

  import Membrane.Helper.GenServer

  alias Membrane.{Element, Pad, Spec}

  alias Membrane.Core.{
    Bin,
    Child,
    PadController,
    PadSpecHandler,
    Parent,
    PadModel,
    PadsSpecs,
    Pipeline,
    Message
  }

  alias Membrane.Core.Bin.{State, LinkingBuffer, SpecController}
  alias Membrane.{CallbackError, Element}
  alias Membrane.Core.Bin.ActionHandler

  require Element
  require Message
  require Pad
  require PadsSpecs
  require PadModel
  require Membrane.PlaybackState

  @type state_t :: Bin.State.t() | Pipeline.State.t()

  @typedoc """
  Defines options that can be passed to `start_link/3` and received
  in `c:handle_init/1` callback.
  """
  @type bin_options_t :: any

  @doc """
  Enables to check whether module is membrane bin.
  """
  @callback membrane_bin? :: true

  @doc """
  Callback invoked on initialization of bin process. It should parse options
  and initialize bin's internal state. Internally it is invoked inside
  `c:GenServer.init/1` callback.
  """
  @callback handle_init(options :: bin_options_t) ::
              {{:ok, Spec.t()}, State.internal_state_t()}
              | {:error, any}

  @doc """
  This function defines a term that allows to reference current bin from Membrane.Spec
  """
  def itself, do: {__MODULE__, :itself}

  @doc PadsSpecs.def_pad_docs(:input, :bin)
  defmacro def_input_pad(name, spec) do
    PadsSpecs.def_bin_pad(name, :input, spec)
  end

  @doc PadsSpecs.def_pad_docs(:output, :bin)
  defmacro def_output_pad(name, spec) do
    PadsSpecs.def_bin_pad(name, :output, spec)
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
          bin_options :: bin_options_t,
          process_options :: GenServer.options()
        ) :: GenServer.on_start()
  def start_link(my_name, module, bin_options \\ nil, process_options \\ []) do
    if module |> bin? do
      debug("""
      Bin start link: module: #{inspect(module)},
      bin options: #{inspect(bin_options)},
      process options: #{inspect(process_options)}
      """)

      GenServer.start_link(__MODULE__, {my_name, module, bin_options}, process_options)
    else
      warn_error(
        """
        Cannot start bin, passed module #{inspect(module)} is not a Membrane Bin.
        Make sure that given module is the right one and it uses Membrane.Bin
        """,
        {:not_bin, module}
      )
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
  def init({my_name, module, bin_options}) do
    {:ok, clock} = Membrane.Clock.start_link(proxy: true)
    with {{:ok, spec}, internal_state} <- module.handle_init(bin_options) do # TODO use CallbackHandler to call init
      state =
        %State{
          internal_state: internal_state,
          bin_options: bin_options,
          module: module,
          name: my_name,
          clock_proxy: clock,
          handlers: handlers(),
          synchronization: %{
            pipeline_clock: clock, # TODO change key name, it is bin clock
            timers: %{},
            clock: nil,
            stream_sync: nil,
            latency: 0
          }
        }
        |> PadSpecHandler.init_pads()

      Message.self(:handle_spec, spec)
      {:ok, state}
    else
      {:error, reason} ->
        raise CallbackError, kind: :error, callback: {module, :handle_init}, reason: reason

      other ->
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

  @impl PlaybackHandler
  def handle_playback_state(old, new, state) do
    Membrane.Core.Parent.handle_playback_state(old, new, state)
  end

  @impl GenServer
  # Bin-specific message.
  # This forwards all :demand, :caps, :buffer, :event
  # messages to an appropriate element.
  def handle_info(Message.new(type, _args, for_pad: pad) = msg, state)
      when type in [:demand, :caps, :buffer, :event] do
    %{linking_buffer: buf} = state

    outgoing_pad =
      pad
      |> Pad.get_corresponding_bin_pad()

    new_buf = LinkingBuffer.store_or_send(buf, msg, outgoing_pad, state)

    {:ok, %{state | linking_buffer: new_buf}} |> noreply()
  end

  # Element-specific message.
  def handle_info(Message.new(:demand_unit, [demand_unit, pad_ref]), state) do
    Child.LifecycleController.handle_demand_unit(demand_unit, pad_ref, state)
    |> noreply()
  end

  def handle_info(message, state) do
    Parent.MessageDispatcher.handle_message(message, state)
    |> noreply(state)
  end

  @impl GenServer
  def handle_call(Message.new(:get_pad_ref, [pad_name, id]), _from, state) do
    PadController.get_pad_ref(pad_name, id, state) |> reply()
  end

  def handle_call(Message.new(:set_controlling_pid, pid), _, state) do
    Child.LifecycleController.handle_controlling_pid(pid, state)
    |> reply()
  end

  def handle_call(
        Message.new(:handle_link, [pad_ref, pad_direction, pid, other_ref, other_info, props]),
        _from,
        state
      ) do
    {{:ok, info}, state} =
      PadController.handle_link(pad_ref, pad_direction, pid, other_ref, other_info, props, state)

    {:ok, new_state} = PadController.handle_linking_finished(state)

    LinkingBuffer.flush_for_pad(state.linking_buffer, pad_ref, new_state)
    ~> {{:ok, info}, %{new_state | linking_buffer: &1}}
    |> reply()
  end

  def handle_call(Message.new(:linking_finished), _, state) do
    PadController.handle_linking_finished(state)
    |> reply()
  end

  def handle_call(Message.new(:handle_watcher, watcher), _, state) do
    Child.LifecycleController.handle_watcher(watcher, state)
    |> reply()
  end

  def set_controlling_pid(server, controlling_pid, timeout \\ 5000) do
    Message.call(server, :set_controlling_pid, controlling_pid, [], timeout)
  end

  @spec handlers :: Parent.MessageDispatcher.handlers()
  defp handlers,
    do: %{
      action_handler: ActionHandler,
      playback_controller: __MODULE__,
      spec_controller: SpecController
    }

  defmacro __using__(_) do
    quote location: :keep do
      use Membrane.Parent
      alias unquote(__MODULE__)
      @behaviour unquote(__MODULE__)

      import Membrane.Element.Base, only: [def_options: 1]
      import unquote(__MODULE__), only: [def_input_pad: 2, def_output_pad: 2]

      require Membrane.Core.PadsSpecs

      Membrane.Core.PadsSpecs.ensure_default_membrane_pads()

      @impl true
      def membrane_bin?, do: true

      @impl true
      def handle_init(_options), do: {{:ok, %Membrane.Spec{}}, %{}}

      @impl true
      def handle_notification(notification, _from, state),
        do: {{:ok, notify: notification}, state}

      defoverridable handle_init: 1,
                     handle_notification: 3
    end
  end
end
