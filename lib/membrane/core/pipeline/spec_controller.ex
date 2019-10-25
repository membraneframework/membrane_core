defmodule Membrane.Core.Pipeline.SpecController do
  use Bunch
  use Membrane.Log, tags: :core

  alias Bunch.Type
  alias Membrane.ParentError
  alias Membrane.Core
  alias Core.Message

  alias Membrane.Core.Parent

  require Message

  @spec resolve_links([Parent.Link.t()], Core.Pipeline.State.t()) ::
          {[Parent.Link.resolved_t()], Core.Pipeline.State.t()}
  def resolve_links(links, state) do
    links
    |> Enum.map(fn %{from: from, to: to} = link ->
      %{link | from: from |> resolve_link(state), to: to |> resolve_link(state)}
    end)
    ~> {&1, state}
  end

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
  @spec link_children([Parent.Link.resolved_t()], Core.Pipeline.State.t()) :: Type.try_t()
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
end
