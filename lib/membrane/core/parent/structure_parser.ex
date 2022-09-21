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
          {[raw_link_t], [ParentSpec.child_spec_extended_t()]} | no_return
  def parse(structure) when is_list(structure) do
    {links, children} =
      structure
      |> List.flatten()
      |> Enum.map(fn
        %ParentSpec.LinkBuilder{links: links, children: children, status: :done} ->
          {Enum.reverse(links), Enum.reverse(children)}

        %ParentSpec.LinkBuilder{links: [%{from: from} | _]} = builder ->
          if length(builder.children) == 1 do
            {[], builder.children}
          else
            raise ParentError,
                  "Invalid link specification: link from #{inspect(from)} lacks its destination."
          end

        {name, child_spec} ->
          {[], {name, child_spec}}

        _other ->
          from_spec_error(structure)
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

  def parse(structure), do: from_spec_error(structure)

  @spec from_spec_error(ParentSpec.structure_spec_t()) :: no_return
  defp from_spec_error(structure) do
    raise ParentError, """
    Invalid structure specification: #{inspect(structure)}.
    See `#{inspect(ParentSpec)}` for information on specifying structure.
    """
  end
end
