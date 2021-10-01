defmodule Membrane.Core.Parent.LinkParser do
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
          pad_props: ParentSpec.pad_props_t()
        }

  @spec parse(ParentSpec.links_spec_t()) ::
          {[raw_link_t], [], ParentSpec.children_spec_t()} | no_return
  def parse(links) when is_list(links) do
    removals =
      links
      |> List.flatten()
      |> Enum.reduce([], fn
        %ParentSpec.LinkDestroyer{} = destroyer, acc ->
          [
            %Link{
              from: %Endpoint{
                child: destroyer.from,
                pad_spec: destroyer.output_pad
              },
              to: %Endpoint{
                child: destroyer.to,
                pad_spec: destroyer.input_pad
              }
            }
            | acc
          ]

        _link, acc ->
          acc
      end)

    {links, children} =
      links
      |> List.flatten()
      |> Enum.map(fn
        %ParentSpec.LinkBuilder{links: links, children: children, status: :done} ->
          {Enum.reverse(links), children}

        %ParentSpec.LinkBuilder{links: [%{from: from} | _]} ->
          raise ParentError,
                "Invalid link specification: link from #{inspect(from)} lacks its destination."

        %ParentSpec.LinkDestroyer{} ->
          {[], []}

        _other ->
          from_spec_error(links)
      end)
      |> Enum.unzip()

    links =
      links
      |> List.flatten()
      |> Enum.map(fn link ->
        %Link{
          from: %Endpoint{
            child: link.from,
            pad_spec: get_pad(link, :from, :output),
            pad_props: Map.get(link, :output_props, [])
          },
          to: %Endpoint{
            child: link.to,
            pad_spec: get_pad(link, :to, :input),
            pad_props: Map.get(link, :input_props, [])
          }
        }
      end)

    children = children |> List.flatten()
    {links, removals, children}
  end

  def parse(links), do: from_spec_error(links)

  @spec from_spec_error([raw_link_t]) :: no_return
  defp from_spec_error(links) do
    raise ParentError, """
    Invalid links specification: #{inspect(links)}.
    See `#{inspect(ParentSpec)}` for information on specifying links.
    """
  end

  defp get_pad(link_spec, child, direction) do
    case link_spec do
      %{^direction => pad_name} -> pad_name
      %{^child => {Membrane.Bin, :itself}} -> Pad.opposite_direction(direction)
      _link_spec -> direction
    end
  end
end
