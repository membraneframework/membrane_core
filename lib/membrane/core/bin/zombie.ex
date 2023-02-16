defmodule Membrane.Core.Bin.Zombie do
  @moduledoc false
  # When a bin returns Membrane.Bin.Action.terminate() and becomes a zombie
  # this module is used to replace the user implementation of the bin
  use Membrane.Bin
  require Membrane.Logger

  # Overrides all the overridable callbacks to add a debug message that the original
  # implementation is not called

  grouped_callbacks =
    Membrane.Bin.behaviour_info(:callbacks)
    |> Enum.group_by(fn callback ->
      cond do
        Module.overridable?(__MODULE__, callback) -> :overridable
        not Module.defines?(__MODULE__, callback) -> :not_implemented
        true -> :ignored
      end
    end)

  grouped_callbacks
  |> Map.get(:grouped_callbacks, [])
  |> Enum.map(fn {name, arity} ->
    args = Enum.map(1..arity//1, &Macro.var(:"arg#{&1}", __MODULE__))

    @impl true
    def unquote(name)(unquote_splicing(args)) do
      Membrane.Logger.debug(
        "Not calling the #{unquote(name)} callback with the following arguments:
        #{Enum.map_join(unquote(args), ", ", &inspect/1)}
        because the bin is in the zombie mode"
      )

      super(unquote_splicing(args))
    end
  end)

  grouped_callbacks
  |> Map.get(:not_implemented)
  |> Enum.map(fn {name, arity} ->
    args = Enum.map(1..arity//1, &Macro.var(:"arg#{&1}", __MODULE__))

    @impl true
    def unquote(name)(unquote_splicing(args)) do
      Membrane.Logger.debug(
        "Not calling the #{unquote(name)} callback with the following arguments:
        #{Enum.map_join(unquote(args), ", ", &inspect/1)}
        because the bin is in the zombie mode"
      )

      state = List.last([unquote_splicing(args)])
      {[], state}
    end
  end)
end
