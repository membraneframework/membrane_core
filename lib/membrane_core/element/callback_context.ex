defmodule Membrane.Element.CallbackContext do
  alias Membrane.Element.CallbackContext, as: Ctx

  @callback from_state(Membrane.Element.Manager.State.t(), keyword()) :: struct()

  @context_mapping %{
    :handle_prepare => Ctx.Prepare,
    :handle_play => Ctx.Play,
    :handle_caps => Ctx.Caps,
    :handle_demand => Ctx.Demand,
    :handle_event => Ctx.Event,
    :handle_other => Ctx.Other,
    :handle_pad_added => Ctx.PadAdded,
    :handle_pad_removed => Ctx.PadRemoved,
    :handle_process => Ctx.Process,
    :handle_stop => Ctx.Stop,
    :handle_write => Ctx.Write
  }

  def construct!(callback, state, entries \\ []) do
    ctx_module = @context_mapping |> Map.get(callback)

    if ctx_module != nil do
      ctx_module.from_state(state, entries)
    else
      raise "No such callback"
    end
  end
end
