defmodule Membrane.Event do
  @moduledoc """
  Event is an entity that can be sent between elements.

  Events can flow either downstream or upstream - they can be sent with
  `t:Membrane.Element.Action.event_t/0`, and can be handled in
  `c:Membrane.Element.Base.handle_event/4`. Each event is
  to implement `Membrane.EventProtocol`, which allows to configure its behaviour.
  """

  @base_fields [metadata: nil]

  @spec event?(any) :: boolean
  def event?(event) do
    if Keyword.has_key?(event.__struct__.__info__(:functions), :event?) and
         Keyword.has_key?(event.__struct__.__info__(:functions), :sticky?) and
         Keyword.has_key?(event.__struct__.__info__(:functions), :async?),
       do: true,
       else: false
  end

  @spec sticky?(any) :: boolean
  def sticky?(event) do
    if event?(event), do: event.__struct__.sticky?(), else: false
  end

  @spec async?(any) :: boolean
  def async?(event) do
    if event?(event), do: event.__struct__.async?(), else: false
  end

  @callback sticky?() :: bool()
  @callback async?() :: bool()

  defmacro def_event_struct(fields) do
    if Keyword.has_key?(fields, :metadata),
      do:
        raise(
          ":metadata field is already defined for each Membrane.Event - you cannot redefine it"
        )

    struct_definition =
      fields
      |> Enum.map(fn {field_name, field_options} ->
        {field_name, Keyword.get(field_options, :default, nil)}
      end)

    types =
      fields
      |> Enum.map(fn {field_name, field_options} ->
        {field_name, Keyword.get(field_options, :type, nil)}
      end)

    quote do
      def event?(), do: true

      @type t :: %__MODULE__{unquote_splicing(types), metadata: map()}
      defstruct unquote(@base_fields) ++ unquote(struct_definition)
    end
  end

  defmacro __using__(_options) do
    quote do
      import Membrane.Event
      @behaviour Membrane.Event

      @implement Membrane.Event
      def sticky?(), do: false

      @implement Membrane.Event
      def async?(), do: false

      defoverridable sticky?: 0, async?: 0
    end
  end
end
