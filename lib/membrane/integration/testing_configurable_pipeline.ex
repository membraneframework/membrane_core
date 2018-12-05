defmodule Membrane.Integration.TestingConfigurablePipeline do
  @moduledoc """
  Provides a testing utility pipeline which can be easily configured from test
  """
  use Membrane.Pipeline

  alias Membrane.Element
  alias Membrane.Pipeline.Spec

  @doc """
  Shortcut for building arguments for starting `TestingConfigurablePipeline`.

  Works only when using standard `input` and `output` pad names.

  ## Examples

      iex> TestingConfigurablePipeline.build_pipeline([el1: MembraneElement1, el2: MembraneElement2], :my_pid)
      %{
        elements: [el1: MembraneElement1, el2: MembraneElement2],
        links: %{{:output, :el1} => {:input, :el2}},
        test_process: :my_pid
      }
  """

  @spec build_pipeline(elements :: Spec.children_spec_t(), pid()) :: map()
  def build_pipeline(elements, test_process) do
    [first_name | element_names] = Enum.map(elements, fn {name, _} -> name end)

    {links, _} =
      Enum.reduce(element_names, {%{}, first_name}, fn x, {links, previous_element} ->
        links = Map.put(links, {:output, previous_element}, {:input, x})
        {links, x}
      end)

    %{
      elements: elements,
      links: links,
      test_process: test_process
    }
  end

  @doc """
  Sends message to a child by Element name.

  ## Examples

      message_child(pipeline, :sink, {:message, "to handle"})
  """

  @spec message_child(pid(), Element.name_t(), any()) :: {:for_element, atom(), atom()}
  def message_child(pipeline, child, message) do
    send(pipeline, {:for_element, child, message})
  end

  @impl true
  def handle_init(%{
        elements: elements,
        links: links,
        test_process: test_process_pid
      }) do
    spec = %Membrane.Pipeline.Spec{
      children: elements,
      links: links
    }

    {{:ok, spec}, %{test_process: test_process_pid}}
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

  defp notify_parent(message, %{test_process: parent} = state) do
    send(parent, {__MODULE__, message})

    {:ok, state}
  end
end
