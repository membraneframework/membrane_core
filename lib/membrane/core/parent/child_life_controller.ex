defmodule Membrane.Core.Parent.ChildLifeController do
  @moduledoc false
  use Bunch

  alias __MODULE__.{StartupHandler, LinkHandler}
  alias Membrane.ParentSpec
  alias Membrane.Core.{Message, Parent}
  alias Membrane.Core.Parent.{ChildEntryParser, ClockHandler, Link}
  alias Membrane.Core.PlaybackHandler

  require Membrane.Logger
  require Membrane.Bin
  require Membrane.Core.Message
  require Membrane.Element
  require Membrane.PlaybackState

  @spec handle_spec(ParentSpec.t(), Parent.state_t()) ::
          {{:ok, [Membrane.Child.name_t()]}, Parent.state_t()} | no_return
  def handle_spec(%ParentSpec{} = spec, state) do
    Membrane.Logger.debug("""
    Initializing spec
    children: #{inspect(spec.children)}
    links: #{inspect(spec.links)}
    """)

    children = ChildEntryParser.from_spec(spec.children)
    :ok = StartupHandler.check_if_children_names_unique(children, state)
    syncs = StartupHandler.setup_syncs(children, spec.stream_sync)

    children =
      StartupHandler.start_children(
        children,
        state.synchronization.clock_proxy,
        syncs,
        state.children_log_metadata
      )

    :ok = StartupHandler.maybe_activate_syncs(syncs, state)
    {:ok, state} = StartupHandler.add_children(children, state)
    state = ClockHandler.choose_clock(children, spec.clock_provider, state)
    {:ok, links} = Link.from_spec(spec.links)
    links = LinkHandler.resolve_links(links, state)
    {:ok, state} = LinkHandler.link_children(links, state)
    children_names = children |> Enum.map(& &1.name)
    {:ok, state} = StartupHandler.exec_handle_spec_started(children_names, state)

    children
    |> Enum.each(&Message.send(&1.pid, :change_playback_state, state.playback.state))

    {{:ok, children_names}, state}
  end

  @spec handle_forward([{Membrane.Child.name_t(), any}], Parent.state_t()) ::
          {:ok | {:error, any}, Parent.state_t()}
  def handle_forward(children_messages, state) do
    result = Bunch.Enum.try_each(children_messages, &do_handle_forward(&1, state))
    {result, state}
  end

  @spec handle_remove_child(Membrane.Child.name_t() | [Membrane.Child.name_t()], Parent.state_t()) ::
          {:ok | {:error, any}, Parent.state_t()}
  def handle_remove_child(children, state) do
    children = children |> Bunch.listify()

    {:ok, state} =
      if state.synchronization.clock_provider.provider in children do
        ClockHandler.reset_clock(state)
      else
        {:ok, state}
      end

    with {:ok, data} <-
           children |> Bunch.Enum.try_map(&Parent.ChildrenModel.get_child_data(state, &1)) do
      data |> Enum.each(&Process.monitor(&1.pid))
      data |> Enum.each(&PlaybackHandler.request_playback_state_change(&1.pid, :terminating))
      :ok
    end
    ~> {&1, state}
  end

  defp do_handle_forward({child_name, message}, state) do
    with {:ok, %{pid: pid}} <- state |> Parent.ChildrenModel.get_child_data(child_name) do
      send(pid, message)
      :ok
    else
      {:error, reason} ->
        {:error, {:cannot_forward_message, [element: child_name, message: message], reason}}
    end
  end
end
