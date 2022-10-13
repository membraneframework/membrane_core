defmodule Membrane.Core.Pipeline.Zombie do
  @moduledoc false
  # When a pipeline returns Membrane.Pipeline.Action.terminate_t()
  # and becomes a zombie-ie-ie oh oh oh oh oh oh oh, ay, oh, ya ya
  # this module is used to replace the user implementation of the pipeline
  use Membrane.Pipeline
  require Membrane.Logger

  # Overrides all the overridable callbacks to add a debug message that the original
  # implementation is not called
  Membrane.Pipeline.behaviour_info(:callbacks)
  |> Enum.filter(&Module.overridable?(__MODULE__, &1))
  |> Enum.map(fn {name, arity} ->
    args = Enum.map(1..arity//1, &Macro.var(:"arg#{&1}", __MODULE__))

    @impl true
    def unquote(name)(unquote_splicing(args)) do
      Membrane.Logger.debug(
        "Not calling the #{unquote(name)} callback with the following arguments:
        #{Enum.map_join(unquote(args), ", ", &inspect/1)}
        because the pipeline is in the zombie mode"
      )

      super(unquote_splicing(args))
    end
  end)
end
