defmodule Membrane.Helper.Doc do
  @moduledoc """
  Module containing helper functions for generating documentation.
  """

  @doc """
  Converts element's known pads information into human-readable markdown
  description.
  """

  alias Membrane.Element.Base.Mixin.CommonBehaviour

  @spec generate_known_pads_docs(CommonBehaviour.known_pads_t) :: String.t
  def generate_known_pads_docs(pads) do
    pads
    |> Enum.map(fn {name, {availability, mode, caps}} ->
      caps_docstring =
        case caps do
          :any ->
            "    * Caps: `any`\n"

          caps when is_list(caps) ->
            "    * Caps:\n" <>
              (caps
               |> Enum.map(&inspect/1)
               |> Enum.map(fn x -> "        * `#{x}`" end)
               |> Enum.join("\n"))

          caps ->
            "    * Caps:\n" <> "      * `#{inspect(caps)}`\n"
        end

      """
      * Pad: `#{inspect(name)}`
          * Availability: #{inspect(availability)}
          * Mode: #{inspect(mode)}
      #{caps_docstring}
      """
    end)
    |> Enum.join("\n")
  end
end
