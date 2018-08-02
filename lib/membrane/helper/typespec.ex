defmodule Membrane.Helper.Typespec do
  @moduledoc """
  Contains helper macro generating typespec from list
  """
  defmacro __using__(_args) do
    quote do
      import Kernel, except: [@: 1]
      import unquote(__MODULE__), only: [@: 1]
    end
  end

  defmacro @{:list_type, _, [{:::, _, [{name, _, _} = name_var, list]}]} do
    type = list |> Enum.reduce(fn a, b -> {:|, [], [a, b]} end)

    quote do
      @type unquote(name_var) :: unquote(type)
      Module.put_attribute(__MODULE__, unquote(name), unquote(list))
    end
  end

  defmacro @expr do
    quote do
      Kernel.@(unquote(expr))
    end
  end
end
