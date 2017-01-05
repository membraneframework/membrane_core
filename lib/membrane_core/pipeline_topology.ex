defmodule Membrane.PipelineTopology do
  @moduledoc """
  Structure representing topology of a pipeline. It can be returned from
  `Membrane.Pipeline.handle_init/1` callback upon pipeline's initialization.
  It will define a fixed topology of child children and links that build the
  pipeline.

  ## Children

  Child children that should be spawned when the pipeline starts can be defined
  with the `:children` field.

  You have to set it to a map, where keys are valid element name (atom or string),
  that is unique within this pipeline and values are either element's module
  (then it will pass no options to its start_link call) or tuple of format
  `{module, options}` where module is the element's module and options is a
  struct of options that is appropriate for given module.

  Sample definition:

      %{
        source:     Membrane.Element.Sample.Source,
        converter:  Membrane.Element.AudioConvert.Converter,
        aggregator: {Membrane.Element.AudioConvert.Aggregator,
          %Membrane.Element.AudioConvert.AggregatorOptions{
            interval: 40 |> Membrane.Time.milliseconds}},
      }

  ## Links

  Links that should be made when the pipeline starts, and children are spawned
  can be defined with the `:links` field.

  You have to set it to a map, where both keys and values are tuples of
  `{element_name, pad_name}`. Element names have to match names given to the
  `:children` field.

  Once it's done, pipeline will ensure that links are present and it will even
  re-link children in case of failure.

  Sample definition:

      %{
        {:source,     :source} => {:converter,  :sink},
        {:converter,  :source} => {:aggregator, :sink},
        {:aggregator, :source} => {:converter,  :sink},
      }
  """

  @type child_spec_t :: module | {module, struct}
  @type children_spec_t :: %{required(Membrane.Element.name_t) => child_spec_t} | nil

  @type link_spec_t :: {Membrane.Element.name_t, Membrane.Pad.name_t}
  @type links_spec_t :: %{required(link_spec_t) => link_spec_t} | nil

  @type t :: %Membrane.PipelineTopology{
    children: children_spec_t,
    links: links_spec_t
  }

  defstruct \
    children: nil,
    links: nil


  # Private API

  @doc false
  # Starts children based on given specification and links them to the current
  # process in the supervision tree.
  #
  # Usually you do not have to call this function, as `Membrane.Pipeline` handles
  # this for you.
  #
  # On success it returns `{:ok, {names_to_pids, pids_to_names}}` where two
  # values returned are maps that allow to easily map child names to process PIDs
  # in both ways.
  #
  # On error it returns `{:error, reason}`.
  #
  # Please note that this function is not atomic and in case of error there's
  # no guarantee that some of children will remain running.
  @spec start_children(children_spec_t) ::
    {:ok, {
      %{required(Membrane.Element.name_t) => pid},
      %{required(pid) => Membrane.Element.name_t}}}
  def start_children(children) when is_map(children) do
    start_children_recurse(children |> Map.to_list, {%{}, %{}})
  end


  # Recursion that starts children processes, final case
  defp start_children_recurse([], acc), do: acc

  # Recursion that starts children processes, case when only module is provided
  defp start_children_recurse([{name, module}|tail], {names_to_pids, pids_to_names}) do
    case Membrane.Element.start_link(module) do
      {:ok, pid} ->
        start_children_recurse(tail, {
          names_to_pids |> Map.put(name, pid),
          pids_to_names |> Map.put(pid, name),
        })

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Recursion that starts children processes, case when both module and options
  # are provided.
  defp start_children_recurse([{name, {module, options}}|tail], {names_to_pids, pids_to_names}) do
    case Membrane.Element.start_link(module, options) do
      {:ok, pid} ->
        start_children_recurse(tail, {
          names_to_pids |> Map.put(name, pid),
          pids_to_names |> Map.put(pid, name),
        })

      {:error, reason} ->
        {:error, reason}
    end
  end
end
