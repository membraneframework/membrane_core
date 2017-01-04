defmodule Membrane.PipelineTopology do
  @moduledoc """
  Structure representing topology of a pipeline. It can be returned from
  `Membrane.Pipeline.handle_init/1` callback upon pipeline's initialization.
  It will define a fixed topology of elements and links that build the pipeline.

  ## Elements

  Elements that should be spawned when the pipeline starts can be defined
  with the `:elements` field.

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

  Links that should be made when the pipeline starts, and elements are spawned
  can be defined with the `:links` field.

  You have to set it to a map, where both keys and values are tuples of
  `{element_name, pad_name}`. Element names have to match names given to the
  `:elements` field.

  Once it's done, pipeline will ensure that links are present and it will even
  re-link elements in case of failure.

  Sample definition:

      %{
        {:source,     :source} => {:converter,  :sink},
        {:converter,  :source} => {:aggregator, :sink},
        {:aggregator, :source} => {:converter,  :sink},
      }
  """

  @type element_def_t :: module | {module, struct}
  @type elements_t :: %{required(Membrane.Element.name_t) => element_def_t} | nil

  @type link_def_t :: {Membrane.Element.name_t, Membrane.Pad.name_t}
  @type links_t :: %{required(link_def_t) => link_def_t} | nil

  @type t :: %Membrane.PipelineTopology{
    elements: elements_t,
    links: links_t
  }

  defstruct \
    elements: nil,
    links: nil
end
