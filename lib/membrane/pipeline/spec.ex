defmodule Membrane.Pipeline.Spec do
  @moduledoc """
  Structure representing topology of a pipeline.

  It can be returned from
  `c:Membrane.Pipeline.handle_init/1` callback upon pipeline's initialization.
  It will define a topology of children and links that build the pipeline.

  ## Children

  Children that should be spawned when the pipeline starts can be defined
  with the `:children` field.

  You have to set it to a keyword list, where keys are valid element name
  that is unique within this pipeline and values are either element's module or
  struct of that module.

  Sample definitions:

      [
        first_element: %Element.With.Options.Struct{option_a: 42},
        some_element: Element.Without.Options,
        other_element: Element.Using.Default.Options
      ]

  When defining children, some additional parameters can be provided by wrapping
  child definition with a tuple and putting keyword list of parameters at the end:

      [
        first_element: {Element.Bare, indexed: true},
        second_element: {%Element{opt_a: 42}, indexed: true}
      ]

  Available params are described in `t:child_property_t/0`

  ## Links

  Links that should be made when the pipeline starts, and children are spawned
  can be defined with the `:links` field.

  You have to set it to a map, where both keys and values are tuples of
  `{element_name, pad_name}`. Entries can also have additional options passed by
  keyword list at the end of a tuple (See `t:endpoint_option_t/0`).
  Element names have to match names given to the `:children` field.

  Once it's done, pipeline will ensure that links are present.

  Sample definition:

      %{
        {:source_a,   :output} => {:converter,  :input, buffer: [preferred_size: 20_000]},
        {:converter,  :output} => {:mixer, :input_a},
        {:source_b,   :output} => {:mixer, :input_b, pad: [mute: true]}
        {:mixer,      :output} => {:sink,  :input, buffer: []},
      }
  """

  alias Membrane.Element
  alias Membrane.Core.PullBuffer
  alias Element.Pad

  @type child_spec_t :: module | struct

  @typedoc """
  Description of all the children elements inside the pipeline
  """
  @type children_spec_t ::
          [{Membrane.Element.name_t(), child_spec_t}]
          | %{Membrane.Element.name_t() => child_spec_t}

  @typedoc """
  Options passed to the element when linking its pad with different one.

  The allowed options are:
  * `:buffer` - allows to configure Buffer between elements. Valid only for input pads.
    See `t:Membrane.Core.PullBuffer.props_t/0`
  * `:pad` - any element-specific options that will be available in pad data
  """
  @type endpoint_options_t :: [
          {:buffer, PullBuffer.props_t()} | {:pad, element_specific_opts :: any()}
        ]

  @typedoc """
  Spec for one of the ends of the link
  """
  @type link_endpoint_spec_t ::
          {Element.name_t(), Pad.name_t()}
          | {Element.name_t(), Pad.name_t(), endpoint_options_t()}

  @typedoc """
  Map describing links between elements
  """
  @type links_spec_t :: %{required(link_endpoint_spec_t) => link_endpoint_spec_t}

  @typedoc """
  Struct used when launching a pipeline
  """
  @type t :: %__MODULE__{
          children: children_spec_t,
          links: links_spec_t
        }

  defstruct children: [],
            links: %{}
end
