defmodule Membrane.Core.Component do
  @moduledoc false

  @type state ::
          Membrane.Core.Pipeline.State.t()
          | Membrane.Core.Bin.State.t()
          | Membrane.Core.Element.State.t()

  @type callback_context_optional_fields ::
          Membrane.Core.Element.CallbackContext.optional_fields()
          | Membrane.Core.Bin.CallbackContext.optional_fields()
          | Membrane.Core.Pipeline.CallbackContext.optional_fields()

  @type callback_context ::
          Membrane.Element.CallbackContext.t()
          | Membrane.Bin.CallbackContext.t()
          | Membrane.Pipeline.CallbackContext.t()

  @spec action_handler(state) :: module
  [Pipeline, Bin, Element]
  |> Enum.map(fn component ->
    def action_handler(%unquote(Module.concat([Membrane.Core, component, State])){}),
      do: unquote(Module.concat([Membrane.Core, component, ActionHandler]))
  end)

  @spec context_from_state(state(), callback_context_optional_fields()) ::
          callback_context()
  def context_from_state(state, args \\ []) do
    alias Membrane.Core.{Bin, Element, Pipeline}

    callback_context_module =
      case state do
        %Element.State{} -> Element.CallbackContext
        %Bin.State{} -> Bin.CallbackContext
        %Pipeline.State{} -> Pipeline.CallbackContext
      end

    callback_context_module.from_state(state, args)
  end

  @spec pipeline?(state) :: boolean()
  def pipeline?(%Membrane.Core.Pipeline.State{}), do: true
  def pipeline?(_state), do: false

  @spec element?(state) :: boolean()
  def element?(%Membrane.Core.Element.State{}), do: true
  def element?(_state), do: false

  @spec bin?(state) :: boolean()
  def bin?(%Membrane.Core.Bin.State{}), do: true
  def bin?(_state), do: false

  @spec child?(state) :: boolean()
  def child?(state), do: element?(state) or bin?(state)

  @spec parent?(state) :: boolean()
  def parent?(state), do: pipeline?(state) or bin?(state)
end
