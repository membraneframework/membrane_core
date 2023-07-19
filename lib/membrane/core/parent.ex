defmodule Membrane.Core.Parent do
  @moduledoc false

  @type state :: Membrane.Core.Bin.State.t() | Membrane.Core.Pipeline.State.t()

  @spec child_pad_removed_error_message(Child.name(), Pad.ref(), module()) :: String.t()
  def child_pad_removed_error_message(child, pad, component_module) do
    component_type_string =
      cond do
        Membrane.Pipeline.pipeline?(component_module) -> "Pipeline"
        Membrane.Bin.bin?(component_module) -> "Bin"
      end

    callback_ref = "`c:Membrane.#{component_type_string}.handle_child_pad_removed/4`"

    """
    Child #{inspect(child)} removed its pad #{inspect(pad)}, but callback #{callback_ref} is not implemented in #{inspect(component_module)}.

    This means, that `#{inspect(child)} is a bin, that removed its pad #{inspect(pad)} on its own, without knowledge of its parent. It
    could be done, by, for example, removing #{inspect(child)}'s child linked to the #{inspect(child)}'s inner pad or by removing link
    between #{inspect(child)} and its child.

    If you want to handle e scenario when a child removes its pad in #{inspect(component_module)}, implement #{callback_ref} callback.
    """
  end
end
