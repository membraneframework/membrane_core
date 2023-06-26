defmodule Membrane.Core.Parent.SpecificationParser do
  @moduledoc false
  use Bunch

  alias Membrane.Core.Parent.Link
  alias Membrane.Core.Parent.Link.Endpoint
  alias Membrane.{ChildrenSpec, Element, Pad, ParentError}

  require Membrane.Logger

  @type raw_link :: %Link{from: raw_endpoint(), to: raw_endpoint()}

  @type raw_endpoint :: %Endpoint{
          child: Element.name() | {Membrane.Bin, :itself},
          pad_spec: Pad.name() | Pad.ref(),
          pad_ref: Pad.ref() | nil,
          pid: pid() | nil,
          pad_props: map()
        }

  @spec parse([ChildrenSpec.builder()]) ::
          {[ChildrenSpec.Builder.child_spec()], [raw_link]} | no_return
  def parse(specifications) when is_list(specifications) do
    {children, links} =
      specifications
      |> List.flatten()
      |> Enum.map(fn
        %ChildrenSpec.Builder{links: links, children: children, status: :done} = builder ->
          if links == [] and children == [] do
            Membrane.Logger.warning(
              "The specification you have passed: #{builder} has no effect - it doesn't produce any children nor links."
            )
          end

          {Enum.reverse(children), Enum.reverse(links)}

        _other ->
          from_spec_error(specifications)
      end)
      |> Enum.unzip()

    links =
      links
      |> List.flatten()
      |> Enum.filter(fn link -> Map.has_key?(link, :from_pad) end)
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
    {children, links}
  end

  def parse(specification), do: from_spec_error([specification])

  @spec from_spec_error([ChildrenSpec.builder()]) :: no_return
  defp from_spec_error(specifications) do
    raise ParentError, """
    Invalid specifications: #{inspect(specifications)}. The link lacks it destination.
    See `#{inspect(ChildrenSpec)}` for information on how to specify children and links
    beween them.
    """
  end
end
