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

  @spec is_pipeline?(state) :: boolean()
  def is_pipeline?(%Membrane.Core.Pipeline.State{}), do: true
  def is_pipeline?(_state), do: false

  @spec is_element?(state) :: boolean()
  def is_element?(%Membrane.Core.Element.State{}), do: true
  def is_element?(_state), do: false

  @spec is_bin?(state) :: boolean()
  def is_bin?(%Membrane.Core.Bin.State{}), do: true
  def is_bin?(_state), do: false

  @spec is_child?(state) :: boolean()
  def is_child?(state), do: is_element?(state) or is_bin?(state)

  @spec is_parent?(state) :: boolean()
  def is_parent?(state), do: is_pipeline?(state) or is_bin?(state)
end
