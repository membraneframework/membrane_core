defmodule Membrane.Support.ChildRemovalTest.Pipeline do
  @moduledoc """
  Module used in tests for elements removing.

  This module allows to build two pipelines:
  * Simple one, with two filters
      source -- filter1 -- [input1] filter2 -- sink
  * Pipeline with two sources (if `extra_source` key is provided in opts).
      source -- filter1 -- [input1] filter2 -- sink
                                    [input2]
                                     /
                    extra_source ___/

  Should be used along with `Membrane.Support.ChildRemovalTest.Pipeline` as they
  share names (i.e. input_pads: `input1` and `input2`) and exchanged messages' formats.
  """
  use Membrane.Pipeline

  def remove_child(pid, child_name) do
    send(pid, {:remove_child, child_name})
  end

  @impl true
  def handle_init(opts) do
    children =
      [
        source: opts.source,
        filter1: opts.filter1,
        filter2: opts.filter2,
        sink: opts.sink
      ]
      |> maybe_add_extra_source(opts)

    links =
      %{
        {:source, :output} => {:filter1, :input1, buffer: [preferred_size: 10]},
        {:filter1, :output} => {:filter2, :input1, buffer: [preferred_size: 10]},
        {:filter2, :output} => {:sink, :input, buffer: [preferred_size: 10]}
      }
      |> maybe_add_extra_source_link(opts)

    spec = %Membrane.Spec{
      children: children,
      links: links
    }

    {{:ok, spec: spec}, %{}}
  end

  @impl true
  def handle_other({:child_msg, name, msg}, state) do
    {{:ok, forward: {name, msg}}, state}
  end

  def handle_other({:remove_child, name}, state) do
    {{:ok, remove_child: name}, state}
  end

  defp maybe_add_extra_source(children, %{extra_source: source}),
    do: [{:extra_source, source} | children]

  defp maybe_add_extra_source(children, _), do: children

  defp maybe_add_extra_source_link(links, %{extra_source: _}) do
    Map.put(links, {:extra_source, :output}, {:filter2, :input2, buffer: [preferred_size: 10]})
  end

  defp maybe_add_extra_source_link(links, _) do
    links
  end
end
