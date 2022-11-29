defmodule Membrane.Core.Pipeline.Zombie do
  @moduledoc false
  # When a pipeline returns Membrane.Pipeline.Action.terminate_t()
  # and becomes a zombie-ie-ie oh oh oh oh oh oh oh, ay, oh, ya ya
  # this module is used to replace the user implementation of the pipeline
  use Membrane.Pipeline
  require Membrane.Logger

  defp log_debug(name, args) do
    Membrane.Logger.debug(
      "Not calling the #{name} callback with the following arguments:
      #{Enum.map_join(args, ", ", &inspect/1)}
      because the pipeline is in the zombie mode"
    )
  end

  # Overrides all the overridable callbacks to add a debug message that the original
  # implementation is not called
  Membrane.Pipeline.behaviour_info(:callbacks)
  |> Enum.map(fn callback ->
    cond do
      Module.overridable?(__MODULE__, callback) ->
        {name, arity} = callback
        args = Enum.map(1..arity//1, &Macro.var(:"arg#{&1}", __MODULE__))

        @impl true
        def unquote(name)(unquote_splicing(args)) do
          log_debug(unquote(name), unquote(args))
          super(unquote_splicing(args))
        end


      callback in Membrane.Pipeline.behaviour_info(:optional_callbacks) ->
        {name, arity} = callback
        args = Enum.map(1..arity//1, &Macro.var(:"arg#{&1}", __MODULE__))

        @impl true
        def unquote(name)(unquote_splicing(args)) do
          log_debug(unquote(name), unquote(args))
          {[], %{}}
        end

      true ->
        :pass
    end
  end)
  |> Enum.reject(&(&1 == :pass))
end
