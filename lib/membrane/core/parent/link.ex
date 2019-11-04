defmodule Membrane.Core.Parent.Link do
  @moduledoc false

  use Bunch

  alias Membrane.{Pad, ParentError, ParentSpec}
  alias __MODULE__.Endpoint

  @enforce_keys [:from, :to]
  defstruct @enforce_keys

  @type t() :: %__MODULE__{from: Endpoint.t(), to: Endpoint.t()}

  @type resolved_t :: %__MODULE__{
          from: Endpoint.resolved_t(),
          to: Endpoint.resolved_t()
        }

  defmodule Endpoint do
    @moduledoc false

    alias Membrane.Element
    alias Membrane.Pad

    @enforce_keys [:child, :pad_spec]
    defstruct @enforce_keys ++ [pad_ref: nil, pid: nil, pad_props: []]

    @type t() :: %__MODULE__{
            child: Element.name_t() | {Membrane.Bin, :itself},
            pad_spec: Pad.name_t() | Pad.ref_t(),
            pad_ref: Pad.ref_t() | nil,
            pid: pid() | nil,
            pad_props: ParentSpec.pad_options_t()
          }

    @type resolved_t() :: %__MODULE__{
            child: Element.name_t() | {Membrane.Bin, :itself},
            pad_spec: Pad.name_t() | Pad.ref_t(),
            pad_ref: Pad.ref_t(),
            pid: pid(),
            pad_props: ParentSpec.pad_options_t()
          }
  end

  @spec from_spec(ParentSpec.links_spec_t()) :: {:ok, [t]} | no_return
  def from_spec(links) when is_list(links) do
    links
    |> List.flatten()
    |> Enum.flat_map(fn
      %ParentSpec.LinkBuilder{links: links, status: :done} ->
        links

      %ParentSpec.LinkBuilder{links: [%{from: from} | _]} ->
        raise ParentError,
              "Invalid link specification: link from #{inspect(from)} lacks its destination."

      links ->
        from_spec(links)
    end)
    |> Enum.map(fn link ->
      %__MODULE__{
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
    ~> {:ok, &1}
  end

  def from_spec(links) do
    raise ParentError, """
    Invalid links specification: #{inspect(links)}.
    See `#{inspect(ParentSpec)}` for information on specifying links.
    """
  end

  defp get_pad(link_spec, child, direction) do
    case link_spec do
      %{^direction => pad_name} -> pad_name
      %{^child => {Membrane.Bin, :itself}} -> Pad.opposite_direction(direction)
      _ -> direction
    end
  end
end
