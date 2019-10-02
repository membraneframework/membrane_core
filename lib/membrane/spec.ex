defmodule Membrane.Spec do
  @moduledoc """
  Structure representing topology of a pipeline/bin.
  It can be returned from
  `c:Membrane.Pipeline.handle_init/1` and `c:Membrane.Bin.handle_init/1` callback upon initialization.
  It will define a topology of children and links that build the pipeline/bin.

  ## Children

  Children that should be spawned when the pipeline/bin starts can be defined
  with the `:children` field.
  You have to set it to a keyword list, where keys are valid children names (`t:Membrane.Child.name_t/0`)
  that are unique within this pipeline/bin and values are either element's module or
  struct of that module.

  Sample definitions:
      [
        first_element: %Element.With.Options.Struct{option_a: 42},
        some_element: Element.Without.Options,
        other_element: Bin.Using.Default.Options
      ]

  ## Pipeline Links

  Links that should be made when the pipeline starts, and children are spawned
  can be defined with the `:links` field.
  You have to set it to a map, where both keys and values are tuples of
  `{element_name, pad_name}`. Entries can also have additional options passed by
  keyword list at the end of a tuple (See `t:endpoint_options_t/0`).
  Element names have to match names given to the `:children` field.
  Once it's done, pipeline will ensure that links are present.

  Sample definition:
      %{
        {:source_a, :output} => {:converter, :input, buffer: [preferred_size: 20_000]},
        {:converter, :output} => {:mixer, :input_a},
        {:source_b, :output} => {:mixer, :input_b, pad: [mute: true]}
        {:mixer, :output} => {:sink, :input, buffer: [warn_size: 264_000, fail_size: 300_000]},
      }
      
  ## Bin links

  For bins boundaries there are special links allowed. User should define links
  between bin's input and first child's input (input-input type) and last
  child's output and bin output (output-output type). In this case, callback module
  creator should name endpoint of the bin with macro `this_bin()`

  Sample definition:

  ```
  %{
    {Bin.itself(), :input} => {:filter1, :input, buffer: [preferred_size: 10]},
    {:filter1, :output} => {:filter2, :input, buffer: [preferred_size: 10]},
    {:filter2, :output} => {Bin.itself(), :output, buffer: [preferred_size: 10]}
  }
  ```

  ## Stream sync

  `:stream_sync` field can be used for specifying elements that should start playing
  at the same moment. An example can be audio and video player sinks. This option
  accepts either `:sinks` atom or list of groups (lists) of elements. Passing `:sinks`
  results in synchronizing all sinks in the pipeline, while passing list of groups
  of elements synchronizes all elements in each group. It is worth mentioning
  that to keep the stream synchronized all involved elements need to rely on
  the same clock.

  By default, no elements are synchronized.

 Sample definitions:

    ```
    %Spec{stream_sync: [[:element1, :element2], [:element3, :element4]]}
    %Spec{stream_sync: :sinks}
    ```

  ## Clock provider

  Clock provider is an element that exports clock that should be used as the pipeline
  clock. The pipeline clock is the default clock used by elements' timers.
  For more information see `Membrane.Element.Base.def_clock/1`.

  """

  alias Membrane.{Element, Pad}
  alias Membrane.Core.InputBuffer

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
  * `:buffer` - keywoed allowing to configure `Membrane.Core.InputBuffer` between elements. Valid only for input pads.
    See `t:Membrane.Core.InputBuffer.props_t/0` for configurable properties.
  * `:pad` - any element-specific options that will be available in `Membrane.Pad.Data` struct.
  """
  @type endpoint_options_t :: [
          {:buffer, InputBuffer.props_t()} | {:pad, element_specific_opts :: any()}
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
          links: links_spec_t,
          stream_sync: :sinks | [[Element.name_t()]],
          clock_provider: Element.name_t()
        }

  defstruct children: [],
            links: %{},
            stream_sync: [],
            clock_provider: nil
end
