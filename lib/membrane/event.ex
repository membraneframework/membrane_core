defmodule Membrane.Event do
  @moduledoc """
  Event is an entity that can be sent between elements.

  Events can flow either downstream or upstream - they can be sent with
  `t:Membrane.Element.Action.event_t/0`, and can be handled in
  `c:Membrane.Element.Base.handle_event/4`. Each event module is about
  to implement `Membrane.Event` behavior, which allows to configure it.
  """

  @typedoc "Type for modules implementing Membrane.Event behaviour"
  @type t :: struct()

  defmodule EventModuleDocGenerator do
    defmacro __before_compile__(env) do
      module = env.module

      moduledoc =
        case Module.get_attribute(module, :moduledoc, "") do
          {_line, doc} -> doc
          doc -> doc
        end

      list_of_fields = Module.get_attribute(module, :list_of_fields)
      full_moduledoc = if moduledoc == false, do: false, else: moduledoc <> list_of_fields

      quote do
        @moduledoc unquote(full_moduledoc)
      end
    end
  end

  @type metadata_t :: map()

  @base_fields metadata: [
                 default: nil,
                 spec:
                   quote do
                     map()
                   end,
                 description: "Metadata"
               ]

  @spec event?(any) :: boolean
  def event?(event) do
    if is_struct(event) and Code.ensure_loaded?(event.__struct__) and
         Keyword.has_key?(event.__struct__.__info__(:functions), :event?) and
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

  defmacro def_event(fields \\ []) do
    if Keyword.has_key?(fields, :metadata),
      do:
        raise(
          ":metadata field is already defined for each Membrane.Event - you cannot redefine it"
        )

    fields = @base_fields ++ fields

    struct_definition =
      fields
      |> Enum.map(fn {field_name, field_options} ->
        {field_name, Keyword.get(field_options, :default, nil)}
      end)

    {fields_typespecs, escaped_fields} = Membrane.Core.OptionsSpecs.parse_opts(fields)

    fields_list =
      if escaped_fields != [],
        do: Membrane.Core.OptionsSpecs.generate_opts_doc(escaped_fields),
        else: []

    quote do
      Module.register_attribute(__MODULE__, :list_of_fields, accumulate: false)

      @list_of_fields """
      ## Available fields
      #{unquote(fields_list)}
      """

      @before_compile EventModuleDocGenerator

      @doc """
      Existence of this function marks the module as the one implementing Membrane.Event behaviour.
      Returns true if the module implements Membrane.Event behaviour.
      """
      def event?(), do: true

      @typedoc """
      Event struct for `#{inspect(__MODULE__)}`
      """
      @type t :: %__MODULE__{unquote_splicing(fields_typespecs), metadata: map()}
      defstruct unquote(struct_definition)
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
