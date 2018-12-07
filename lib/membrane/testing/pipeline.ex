defmodule Membrane.Testing.Pipeline do
  @moduledoc """
  Provides a testing utility pipeline which can be easily configured from test.
  """

  use Membrane.Pipeline

  alias Membrane.Element
  alias Membrane.Pipeline.Spec

  defmodule Options do
    @moduledoc """
    Structure representing `options` passed to testing pipeline.

    ## Monitored Callbacks
    List of callback names that shall be sent to process in `test_process` field

    ##  Test Process
    `pid` of process that shall receive messages about Pipeline state.

    ## Elements
    List of element specs.

    ## Links
    If links is not present or set to nil it will be populated automatically based on elements order using default pad names.
    """

    @enforce_keys [:elements, :test_process]
    defstruct @enforce_keys ++ [:monitored_callbacks, :links]

    @type pipeline_callback ::
            :handle_notification
            | :handle_playing_to_prepared
            | :handle_prepared_to_playing
            | :handle_prepared_to_stopped
            | :handle_stopped_to_prepared

    @type t :: %__MODULE__{
            monitored_callbacks: pipeline_callback(),
            test_process: pid(),
            elements: Spec.children_spec_t(),
            links: Spec.links_spec_t()
          }
  end

  @doc """
  Links subsequent elements using default pads (linking `:input` to `:output` of previous element).

  ## Examples

      iex> Pipeline.populate_links([el1: MembraneElement1, el2: MembraneElement2])
      %{{:el1, :output} => {:el2, :input}}
  """
  @spec populate_links(elements :: Spec.children_spec_t()) :: Spec.links_spec_t()
  def populate_links(elements) do
    [first_name | element_names] = Enum.map(elements, fn {name, _} -> name end)

    {links, _} =
      Enum.reduce(element_names, {%{}, first_name}, fn x, {links, previous_element} ->
        links = Map.put(links, {previous_element, :output}, {x, :input})
        {links, x}
      end)

    links
  end

  @doc """
  Sends message to a child by Element name.

  ## Examples

      message_child(pipeline, :sink, {:message, "to handle"})
  """
  @spec message_child(pid(), Element.name_t(), any()) :: :ok
  def message_child(pipeline, child, message) do
    send(pipeline, {:for_element, child, message})
    :ok
  end

  @impl true
  def handle_init(options)

  def handle_init(%Options{monitored_callbacks: nil} = options),
    do: handle_init(%Options{options | monitored_callbacks: []})

  def handle_init(%Options{links: nil, elements: elements} = options) do
    new_links = populate_links(elements)
    handle_init(%Options{options | links: new_links})
  end

  def handle_init(args) do
    %Options{elements: elements, links: links} = args

    spec = %Membrane.Pipeline.Spec{
      children: elements,
      links: links
    }

    new_state = Map.take(args, [:monitored_callbacks, :test_process])
    {{:ok, spec}, new_state}
  end

  @impl true
  def handle_stopped_to_prepared(state),
    do: notify_parent(:handle_stopped_to_prepared, state)

  @impl true
  def handle_playing_to_prepared(state),
    do: notify_parent(:handle_playing_to_prepared, state)

  @impl true
  def handle_prepared_to_playing(state),
    do: notify_parent(:handle_prepared_to_playing, state)

  @impl true
  def handle_prepared_to_stopped(state),
    do: notify_parent(:handle_prepared_to_stopped, state)

  @impl true
  def handle_notification(notification, from, state),
    do: notify_parent({:handle_notification, {notification, from}}, state)

  @impl true
  def handle_other({:for_element, element, message}, state) do
    {{:ok, forward: {element, message}}, state}
  end

  def handle_other(message, state),
    do: notify_parent({:handle_other, message}, state)

  defp get_callback_name(name) when is_atom(name), do: name
  defp get_callback_name({name, _}), do: name

  defp notify_parent(message, state) do
    %{test_process: parent, monitored_callbacks: monitored_callbacks} = state

    if get_callback_name(message) in monitored_callbacks do
      send(parent, {__MODULE__, message})
    end

    {:ok, state}
  end
end
