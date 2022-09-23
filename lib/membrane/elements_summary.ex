defmodule Membrane.CallbackSummary do
  @moduledoc """
  Below there is a list of callbacks to be implemented by each componen type.
  ## Filter
  #{DocsHelper.generate_callbacks_description(Membrane.Filter)}

  ## Source
  #{DocsHelper.generate_callbacks_description(Membrane.Source)}

  ## Sink
  #{DocsHelper.generate_callbacks_description(Membrane.Sink)}

  ## Pipeline
  #{DocsHelper.generate_callbacks_description(Membrane.Pipeline)}

  ## Bin
  #{DocsHelper.generate_callbacks_description(Membrane.Bin)}
  """
end
