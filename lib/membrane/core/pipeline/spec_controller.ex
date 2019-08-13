defmodule Membrane.Core.Pipeline.SpecController do
  use Bunch
  use Membrane.Log, tags: :core

  @behaviour Membrane.Core.SpecController

  alias Membrane.Core
  alias Membrane.{Spec, PipelineError}
  alias Membrane.Core.{
    ParentState,
    Message,
    CallbackHandler
  }

  alias Membrane.Element

  require Message

  @spec handle_spec(Spec.t(), State.t()) :: Type.stateful_try_t([Element.name_t()], State.t())
  def handle_spec(%Spec{children: children_spec, links: links}, state) do
    Core.SpecController.handle_spec(__MODULE__, %{children: children_spec, links: links}, state)
  end

  @impl true
  def resolve_links(links, state) do
    links
    |> Enum.map(fn %{from: from, to: to} = link ->
      %{link | from: from |> resolve_link(state), to: to |> resolve_link(state)}
    end)
    ~> {&1, state}
  end

  defp resolve_link(%{element: element, pad_name: pad_name, id: id} = endpoint, state) do
    with {:ok, pid} <- state |> ParentState.get_child_pid(element),
         {:ok, pad_ref} <- pid |> Message.call(:get_pad_ref, [pad_name, id]) do
      %{endpoint | pid: pid, pad_ref: pad_ref}
    else
      {:error, {:unknown_child, child}} ->
        raise PipelineError, "Child #{inspect(child)} does not exist"

      {:error, {:cannot_handle_message, :unknown_pad, _ctx}} ->
        raise PipelineError, "Child #{inspect(element)} does not have pad #{inspect(pad_name)}"

      {:error, reason} ->
        raise PipelineError, """
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
    with :ok <- links |> Bunch.Enum.try_each(&Element.link/1),
         :ok <-
           state
           |> ParentState.get_children()
           |> Bunch.Enum.try_each(fn {_pid, pid} -> pid |> Element.handle_linking_finished() end),
         do: {:ok, state}
  end

  @impl true
  def exec_handle_spec_started(children_names, state) do
    callback_res =
      CallbackHandler.exec_and_handle_callback(
        :handle_spec_started,
        Membrane.Pipeline,
        [children_names],
        state
      )

    with {:ok, _} <- callback_res do
      callback_res
    else
      {{:error, reason}, state} ->
        raise PipelineError, """
        Callback :handle_spec_started failed with reason: #{inspect(reason)}
        Pipeline state: #{inspect(state, pretty: true)}
        """
    end
  end
end
