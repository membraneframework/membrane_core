defmodule Membrane.Core.Component do
  @moduledoc false

  @type state_t ::
          Membrane.Core.Pipeline.State.t()
          | Membrane.Core.Bin.State.t()
          | Membrane.Core.Element.State.t()

  @type callback_context_option_t ::
          Membrane.Element.CallbackContext.option_t()
          | Membrane.Bin.CallbackContext.option_t()
          | Membrane.Pipeline.CallbackContext.option_t()

  @type callback_context_options_t :: [callback_context_option_t()]

  @type callback_context_t ::
          Membrane.Element.CallbackContext.t()
          | Membrane.Bin.CallbackContext.t()
          | Membrane.Pipeline.CallbackContext.t()

  @spec action_handler(state_t) :: module
  [Pipeline, Bin, Element]
  |> Enum.map(fn component ->
    def action_handler(%unquote(Module.concat([Membrane.Core, component, State])){}),
      do: unquote(Module.concat([Membrane.Core, component, ActionHandler]))
  end)

  @spec callback_context(state_t(), callback_context_options_t()) ::
          callback_context_t()
  # def callback_context(state, args \\ [])

  # [Pipeline, Bin, Element]
  # |> Enum.map(fn component ->
  #   def callback_context(
  #         %unquote(Module.concat([Membrane.Core, component, State])){} = state,
  #         args
  #       ),
  #       do: unquote(Module.concat([Membrane, component, CallbackContext])).from_state(state, args)
  # end)

  def callback_context(state, args \\ []) do
    callback_context_module =
      case state do
        %Membrane.Core.Element.State{} -> Membrane.Element.CallbackContext
        %Membrane.Core.Bin.State{} -> Membrane.Bin.CallbackContext
        %Membrane.Core.Pipeline.State{} -> Membrane.Pipeline.CallbackContext
      end

    callback_context_module.from_state(state, args)
  end

  # defmacro callback_context_generator(restrict, module, state, args \\ []) do
  #   module = Macro.expand(module, __ENV__)

  #   restrict =
  #     case restrict do
  #       :parent -> [Pipeline, Bin]
  #       :child -> [Bin, Element]
  #       :any -> [Pipeline, Bin, Element]
  #       restrict -> restrict
  #     end

  #   requires =
  #     restrict
  #     |> Enum.map(fn component ->
  #       quote do
  #         require unquote(context(component, module))
  #       end
  #     end)

  #   clauses =
  #     restrict
  #     |> Enum.flat_map(fn component ->
  #       quote do
  #         %unquote(state(component)){} ->
  #           &unquote(context(component, module)).from_state(&1, unquote(args))
  #       end
  #     end)

  #   quote do
  #     unquote_splicing(requires)
  #     unquote({:case, [], [state, [do: clauses]]})
  #   end
  # end

  @spec is_pipeline?(state_t) :: boolean()
  def is_pipeline?(%Membrane.Core.Pipeline.State{}), do: true
  def is_pipeline?(_state), do: false

  @spec is_element?(state_t) :: boolean()
  def is_element?(%Membrane.Core.Element.State{}), do: true
  def is_element?(_state), do: false

  @spec is_bin?(state_t) :: boolean()
  def is_bin?(%Membrane.Core.Bin.State{}), do: true
  def is_bin?(_state), do: false

  @spec is_child?(state_t) :: boolean()
  def is_child?(state), do: is_element?(state) or is_bin?(state)

  @spec is_parent?(state_t) :: boolean()
  def is_parent?(state), do: is_pipeline?(state) or is_bin?(state)

  # defp context(component, module),
  #   do: Module.concat([Membrane, component, CallbackContext, module])

  # defp state(component), do: Module.concat([Membrane.Core, component, State])
end
