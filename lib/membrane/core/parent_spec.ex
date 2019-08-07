defmodule Membrane.Core.ParentSpec do
  defmacro __using__(_) do
    quote do
      alias Membrane.Core.InputBuffer
      alias Element.Pad
      alias Membrane.Core.ParentUtils

      @type child_spec_t :: module | struct

      @typedoc """
      Description of all the children elements
      """
      @type children_spec_t ::
              [{ParentUtils.child_name_t(), child_spec_t}]
              | %{ParentUtils.child_name_t() => child_spec_t}

      @typedoc """
      Options passed to the element when linking its pad with different one.

      The allowed options are:
      * `:buffer` - keywoed allowing to configure `Membrane.Core.InputBuffer` between elements. Valid only for input pads.
      See `t:Membrane.Core.InputBuffer.props_t/0` for configurable properties.
      * `:pad` - any element-specific options that will be available in `Membrane.Element.Pad.Data` struct.
      """
      @type endpoint_options_t :: [
              {:buffer, InputBuffer.props_t()} | {:pad, element_specific_opts :: any()}
            ]

      @typedoc """
      Spec for one of the ends of the link
      """
      @type link_endpoint_spec_t ::
              {ParentUtils.child_name_t(), Pad.name_t()}
              | {ParentUtils.child_name_t(), Pad.name_t(), endpoint_options_t()}

      @typedoc """
      Map describing links between elements
      """
      @type links_spec_t :: %{required(link_endpoint_spec_t) => link_endpoint_spec_t}

      @typedoc """
      Struct used when launching a pipeline or bin
      """
      # Because we want to be backward compatible and still be able to use Pipeline.Spec
      # and not have a common Spec struct we make this __using__()
      @type t :: %__ENV__.module(){
              children: children_spec_t,
              links: links_spec_t
            }

      defstruct children: [],
                links: %{}
    end
  end
end
