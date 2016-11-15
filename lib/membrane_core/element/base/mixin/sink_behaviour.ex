defmodule Membrane.Element.Base.Mixin.SinkBehaviour do
  @doc """
  Callback that is called when buffer arrives.

  The arguments are:

  - buffer
  - current element state

  While implementing these callbacks, please use pattern matching to define
  what caps are supported. In other words, define one function matching this
  signature per each caps supported.
  """
  @callback handle_buffer(%Membrane.Buffer{}, any) ::
    {:ok, any} |
    {:send, [%Membrane.Buffer{}], any} |
    {:error, any, any}


  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Membrane.Element.Base.Mixin.SinkBehaviour
    end
  end
end
