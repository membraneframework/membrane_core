defmodule Membrane.Element.Base.Mixin.Process do
  @moduledoc """
  This module is a mixin with common routines regarding spawning element
  as a process.

  You should not use this directly unless you know what are you doing
  """


  defmacro __using__(_) do
    quote do
      use GenServer


    end
  end
end
