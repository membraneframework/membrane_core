defmodule Membrane.Core.SpecController do
  use Membrane.Core.PlaybackRequestor
  use Membrane.Log, tags: :core

  alias Membrane.Core.ChildrenController
  alias Bunch.Type
  # TODO Link should be moved out of Pipeline
  alias Membrane.Core.Pipeline.Link

  @callback resolve_links([Link.t()], State.t()) :: [Link.resolved_t()]

  @callback link_children([Link.resolved_t()], ParentState.t()) :: Type.try_t()

  @callback exec_handle_spec_started([ChildrenController.child_name_t()], ParentState.t()) ::
              {:ok, ParentState.t()}

  def handle_spec(spec_controller_module, %{children: children_spec, links: links}, state) do
    debug("""
    Initializing spec
    children: #{inspect(children_spec)}
    links: #{inspect(links)}
    """)
    parsed_children = children_spec |> ChildrenController.parse_children()

    {:ok, state} =
      {parsed_children |> ChildrenController.check_if_children_names_unique(state), state}

    children = parsed_children |> ChildrenController.start_children()
    {:ok, state} = children |> ChildrenController.add_children(state)

    {{:ok, links}, state} = {links |> parse_links(), state}
    {links, state} = links |> spec_controller_module.resolve_links(state)
    {:ok, state} = links |> spec_controller_module.link_children(state)
    {children_names, children_pids} = children |> Enum.unzip()
    {:ok, state} = {children_pids |> ChildrenController.set_children_watcher(), state}
    {:ok, state} = spec_controller_module.exec_handle_spec_started(children_names, state)

    children_pids
    |> Enum.each(&change_playback_state(&1, state.playback.state))

    {{:ok, children_names}, state}
  end

  defp parse_links(links), do: links |> Bunch.Enum.try_map(&Link.parse/1)
end
