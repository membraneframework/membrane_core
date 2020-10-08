defmodule Membrane.Core.Child do
  @moduledoc false

  @type state_t :: Membrane.Core.Element.State.t() | Membrane.Core.Bin.State.t()

  @docs_order [
    :membrane_options_moduledoc,
    :membrane_pads_moduledoc,
    :membrane_clock_moduledoc
  ]

  @spec generate_moduledoc(module, :element | :bin) :: Macro.t()
  def generate_moduledoc(module, child_type) do
    membrane_pads_moduledoc =
      Module.get_attribute(module, :membrane_pads)
      |> __MODULE__.PadsSpecs.generate_docs_from_pads_specs()

    Module.put_attribute(module, :membrane_pads_moduledoc, membrane_pads_moduledoc)

    moduledoc =
      case Module.get_attribute(module, :moduledoc, "") do
        {_line, doc} -> doc
        doc -> doc
      end

    if moduledoc != false do
      moduledoc =
        if String.trim(moduledoc) == "" do
          "Membrane #{child_type}.\n\n"
        else
          moduledoc
        end

      moduledoc =
        @docs_order
        |> Enum.map(&Module.get_attribute(module, &1))
        |> Enum.filter(& &1)
        |> Enum.reduce(moduledoc, fn doc, moduledoc ->
          quote do
            unquote(moduledoc) <> unquote(doc)
          end
        end)

      quote do
        @moduledoc unquote(moduledoc)
      end
    end
  end
end
