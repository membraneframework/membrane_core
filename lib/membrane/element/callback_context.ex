defmodule Membrane.Element.CallbackContext do
  @moduledoc """
  Parent module for all contexts passed to callbacks. Provides a convenient way
  to create them
  """
  alias Membrane.Element.CallbackContext, as: Ctx

  @callback from_state(Membrane.Element.Manager.State.t(), Enum.t()) :: struct()

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

  @type callback_t() ::
          :handle_prepare
          | :handle_play
          | :handle_caps
          | :handle_demand
          | :handle_event
          | :handle_other
          | :handle_pad_added
          | :handle_pad_removed
          | :handle_process
          | :handle_stop
          | :handle_write

  @doc """
  Provides a proper Context struct for a callback.
  """
  @spec construct!(
          context :: callback_t(),
          state :: Membrane.Element.Manager.State.t(),
          entries :: Enum.t()
        ) :: struct()
  def construct!(callback, state, entries \\ []) do
    ctx_module = @context_mapping |> Map.get(callback)

    if ctx_module != nil do
      ctx_module.from_state(state, entries)
    else
      raise "No such callback"
    end
  end
end
