defmodule Membrane.Element.Base.Mixin.CommonInfos do
  @moduledoc false

  # This module is a mixin with common routines for all elements regarding
  # infos they may receive.


  defmacro __using__(_) do
    quote location: :keep do
      @doc false
      def handle_info(message, %{element_state: element_state} = state) do
        __MODULE__.handle_other(message, element_state) |> handle_callback(state)
      end
    end
  end
end
