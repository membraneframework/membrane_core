defmodule Membrane.Support.ChildRemovalTest.Pipeline do
  @moduledoc """
  Module used in tests for elements removing.

  This module allows to build two pipelines:
  * Simple one, with two filters
      source -- filter1 -- [input1] filter2 -- sink
  * Pipeline with two sources (if `extra_source` key is provided in opts).
      source -- filter1 -- filter2 -- [input1] filter3 -- sink
                                               [input2]
                                                 /
                                extra_source ___/

  Should be used along with `Membrane.Support.ChildRemovalTest.Pipeline` as they
  share names (i.e. input_pads: `input1` and `input2`) and exchanged messages' formats.
  """
  use Membrane.Pipeline

  @spec remove_child(pid(), Membrane.Child.name_t()) :: any()
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
        filter3: opts.filter3,
        sink: opts.sink
      ]
      |> maybe_add_extra_source(opts)

    links =
      [
        link(:source)
        |> via_in(:input1, target_queue_size: 10)
        |> to(:filter1)
        |> via_in(:input1, target_queue_size: 10)
        |> to(:filter2)
        |> via_in(:input1, target_queue_size: 10)
        |> to(:filter3)
        |> via_in(:input, target_queue_size: 10)
        |> to(:sink)
      ]
      |> maybe_add_extra_source_link(opts)

    spec = %Membrane.ParentSpec{
      children: children,
      links: links
    }

    {{:ok, spec: spec, playback: :playing}, %{}}
  end

  @impl true
  def handle_info({:child_msg, name, msg}, _ctx, state) do
    {{:ok, notify_child: {name, msg}}, state}
  end

  @impl true
  def handle_info({:remove_child, name}, _ctx, state) do
    {{:ok, remove_child: name}, state}
  end

  defp maybe_add_extra_source(children, %{extra_source: source}),
    do: [{:extra_source, source} | children]

  defp maybe_add_extra_source(children, _opts), do: children

  defp maybe_add_extra_source_link(links, %{extra_source: _}) do
    [
      link(:extra_source) |> via_in(:input2, target_queue_size: 10) |> to(:filter3)
      | links
    ]
  end

  defp maybe_add_extra_source_link(links, _opts) do
    links
  end
end
