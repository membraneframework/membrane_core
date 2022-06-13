defmodule Membrane.Event do
  @moduledoc """
  Event is an entity that can be sent between elements.

  Events can flow either downstream or upstream - they can be sent with
  `t:Membrane.Element.Action.event_t/0`, and can be handled in
  `c:Membrane.Element.Base.handle_event/4`. Each event is
  to implement `Membrane.EventProtocol`, which allows to configure its behaviour.
  """

  @base_fields [metadata: nil]
  @type t :: EventProtocol.t()

  @spec event?(t()) :: boolean
  def event?(event) do
    if Keyword.has_key?(event.__struct__.__info__(:functions), :sticky?) and
         Keyword.has_key?(event.__struct__.__info__(:functions), :async?),
       do: true,
       else: false
  end

  @callback sticky?(Event.t()) :: bool()

  @callback async?(Event.t()) :: bool()

  defmacro def_event_struct(fields) do
    struct_definition = fields |> Enum.map(fn {field_name, field_options} -> {field_name, Keyword.get(field_options, :default, nil)} end)
    types = fields |> Enum.map(fn {field_name, field_options} -> {field_name, Keyword.get(field_options, :type, nil)} end)
    quote do
      @type t :: %__MODULE__{unquote_splicing(types)}
      defstruct unquote(@base_fields) ++ unquote(struct_definition)
    end
  end

  defmacro __using__(options) do
    base =
      quote do
        import Membrane.Event
        @behaviour Membrane.Event
      end
    sticky_implementation =
      if Keyword.has_key?(options, :sticky?) do
        quote do
          @impl Membrane.Event
          def sticky?(event), do: unquote(Keyword.get(options, :sticky?)).(event)
        end
      else
        quote do
          @impl Membrane.Event
          def sticky?(_event), do: false
        end
      end

    async_implementation =
      if Keyword.has_key?(options, :async?) do
        quote do
          @impl Membrane.Event
          def async?(event), do: unquote(Keyword.get(options, :async?)).(event)
        end
      else
        quote do
          @impl Membrane.Event
          def async?(_event), do: false
        end
      end
    [base, sticky_implementation, async_implementation]
  end
end
