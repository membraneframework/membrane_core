defmodule Membrane.Core.Parent.StructureParser do
  @moduledoc false
  use Bunch

  alias Membrane.Core.Parent.Link
  alias Membrane.Core.Parent.Link.Endpoint
  alias Membrane.{Element, Pad, ParentError, ParentSpec}

  @type raw_link_t :: %Link{from: raw_endpoint_t(), to: raw_endpoint_t()}

  @type raw_endpoint_t :: %Endpoint{
          child: Element.name_t() | {Membrane.Bin, :itself},
          pad_spec: Pad.name_t() | Pad.ref_t(),
          pad_ref: Pad.ref_t() | nil,
          pid: pid() | nil,
          pad_props: map()
        }

  @spec parse(ParentSpec.structure_spec_t()) ::
          {[raw_link_t], [ParentSpec.child_spec_t()]} | no_return
  def parse(links) when is_list(links) do
    {links, children} =
      links
      |> List.flatten()
      |> Enum.map(fn
        %ParentSpec.LinkBuilder{links: links, children: children, status: :done} ->
          {Enum.reverse(links), Enum.reverse(children)}

        %ParentSpec.LinkBuilder{links: [%{from: from} | _]} ->
          raise ParentError,
                "Invalid link specification: link from #{inspect(from)} lacks its destination."

        {name, child_spec} ->
          {[], {name, child_spec}}

        _other ->
          from_spec_error(links)
      end)
      |> Enum.unzip()

    links =
      links
      |> List.flatten()
      |> Enum.map(fn %{} = link ->
        %Link{
          id: make_ref(),
          from: %Endpoint{
            child: link.from,
            pad_spec: link.from_pad,
            pad_props: link.from_pad_props
          },
          to: %Endpoint{
            child: link.to,
            pad_spec: link.to_pad,
            pad_props: link.to_pad_props
          }
        }
      end)

    children = children |> List.flatten()
    {links, children}
  end

  def parse(links), do: from_spec_error(links)

  @spec from_spec_error([raw_link_t]) :: no_return
  defp from_spec_error(links) do
    raise ParentError, """
    Invalid links specification: #{inspect(links)}.
    See `#{inspect(ParentSpec)}` for information on specifying links.
    """
  end
end
