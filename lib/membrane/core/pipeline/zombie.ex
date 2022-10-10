defmodule Membrane.Core.Pipeline.Zombie do
  @moduledoc false
  # When a pipeline returns Membrane.Pipeline.Action.terminate_t()
  # and becomes a zombie-ie-ie oh oh oh oh oh oh oh, ay, oh, ya ya
  # this module is used to replace the user implementation of the pipeline
  use Membrane.Pipeline
end
