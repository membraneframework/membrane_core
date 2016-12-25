defmodule Membrane.Helper.Doc do
  @moduledoc """
  Module containing helper functions for generating documentation.
  """


  @doc """
  Converts element's known pads information into human-readable markdown
  description.
  """
  @spec generate_known_pads_docs(Membrane.Pad.known_pads_t) :: String.t
  def generate_known_pads_docs(pads) do
    pads
    |> Enum.map(fn({name, {availability, caps}}) ->
      caps_docstring = case caps do
        :any ->
          "    * Caps: any\n"
        caps ->
          "    * Caps:\n" <>
          (
            caps
            |> Enum.map(&inspect/1)
            |> Enum.map(fn(x) -> "        * `#{x}`" end)
            |> Enum.join("\n")
          )
      end

      """
      * Pad: `#{inspect(name)}`
          * Availability: #{availability}
      #{caps_docstring}
      """
    end)
    |> Enum.join("\n")
  end
end
