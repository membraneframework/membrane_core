defmodule Membrane.Core.Pipeline.SpecController do
  use Bunch
  use Membrane.Log, tags: :core

  @behaviour Membrane.Core.Parent.ChildrenController

  alias Membrane.ParentError
  alias Membrane.Core
  alias Core.{Link, Message}

  alias Membrane.Core.Parent

  require Message

  @impl true
  def resolve_links(links, state) do
    links
    |> Enum.map(fn %{from: from, to: to} = link ->
      %{link | from: from |> resolve_link(state), to: to |> resolve_link(state)}
    end)
    ~> {&1, state}
  end

  @spec resolve_link(Link.Endpoint.t(), Parent.ChildrenModel.t()) ::
          Link.Endpoint.t() | {:error, reason :: any()}
  def resolve_link(%{element: element, pad_name: pad_name, id: id} = endpoint, state) do
    with {:ok, %{pid: pid}} <- state |> Parent.ChildrenModel.get_child_data(element),
         {:ok, pad_ref} <- pid |> Message.call(:get_pad_ref, [pad_name, id]) do
      %{endpoint | pid: pid, pad_ref: pad_ref}
    else
      {:error, {:unknown_child, child}} ->
        raise ParentError, "Child #{inspect(child)} does not exist"

      {:error, {:cannot_handle_message, :unknown_pad, _ctx}} ->
        raise ParentError, "Child #{inspect(element)} does not have pad #{inspect(pad_name)}"

      {:error, reason} ->
        raise ParentError, """
        Error resolving pad #{inspect(pad_name)} of element #{inspect(element)}, \
        reason: #{inspect(reason, pretty: true)}\
        """
    end
  end

  # Links children based on given specification and map for mapping children
  # names into PIDs.
  #
  # Please note that this function is not atomic and in case of error there's
  # a chance that some of children will remain linked.
  @impl true
  def link_children(links, state) do
    with :ok <- links |> Bunch.Enum.try_each(&Core.Element.link/1),
         :ok <-
           state
           |> Parent.ChildrenModel.get_children()
           |> Bunch.Enum.try_each(fn {_name, %{pid: pid}} ->
             pid |> Message.call(:linking_finished, [])
           end),
         do: {:ok, state}
  end

  @impl true
  def action_handler_module, do: Membrane.Pipeline
end
