defmodule Membrane.Element.Base do
  @moduledoc """
  Modules in this namespace contain behaviours, default callback implementations
  and other stuff useful when creating elements.

  Elements are units that produce, process or consume data. They can be linked
  with `Membrane.Pipeline`, and thus form a pipeline able to perform complex data
  processing. Each element defines set of pads, which are used as interface
  through which such linking is possible. During playback, pads can either send
  (source pads) or receive (sink pads) data. For more information on pads, see
  `Membrane.Element.Pad`.

  To implement an element, one of base modules (`Membrane.Element.Base.Source`,
  `Membrane.Element.Base.Filter`, `Membrane.Element.Base.Sink`)
  has to be `use`d, depending on the element type:
  - source, producing buffers (contain only source pads),
  - filter, processing buffers (contain both sink and source pads),
  - sink, consuming buffers (contain only sink pads).
  For more information on each element type, check documentation for appropriate
  base module.

  ## Behaviours
  Element-specific behaviours are specified in modules:
  - `Membrane.Element.Base.Mixin.CommonBehaviour` - behaviour common to all
  elements,
  - `Membrane.Element.Base.Mixin.SourceBehaviour` - behaviour common to sources
  and filters,
  - `Membrane.Element.Base.Mixin.SinkBehaviour` - behaviour common to sinks and
  filters,
  - Base modules (`Membrane.Element.Base.Source`, `Membrane.Element.Base.Filter`,
  `Membrane.Element.Base.Sink`) - behaviours specific to each element type.

  ## Callbacks
  Modules listed above provide specifications of callbacks that define elements
  lifecycle. All of these callbacks have names with the `handle_` prefix.
  They are used to define reaction to certain events that happen during runtime,
  and indicate what actions frawork should undertake as a result, besides
  executing element-specific code.

  For actions that can be returned by each callback, see `Membrane.Element.Action`
  module.
  """
end
