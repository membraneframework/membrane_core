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

    @enforce_keys [:element, :pad_name]
    defstruct element: nil, pad_name: nil, id: nil, pad_ref: nil, pid: nil, opts: []

    @type t() :: %__MODULE__{
            element: Element.name_t() | {Membrane.Bin, :itself},
            pad_name: Pad.name_t(),
            id: Pad.dynamic_id_t() | nil,
            pad_ref: Pad.ref_t() | nil,
            pid: pid() | nil,
            opts: ParentSpec.pad_options_t()
          }

    @type resolved_t() :: %__MODULE__{
            element: Element.name_t() | {Membrane.Bin, :itself},
            pad_name: Pad.name_t(),
            id: Pad.dynamic_id_t() | nil,
            pad_ref: Pad.ref_t(),
            pid: pid(),
            opts: ParentSpec.pad_options_t()
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
          element: link.from,
          pad_name: get_pad_name(link, :from, :output),
          id: Map.get(link, :output_id),
          opts: Map.get(link, :output_opts, [])
        },
        to: %Endpoint{
          element: link.to,
          pad_name: get_pad_name(link, :to, :input),
          id: Map.get(link, :input_id),
          opts: Map.get(link, :input_opts, [])
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

  defp get_pad_name(link_spec, child, direction) do
    case link_spec do
      %{^direction => pad_name} -> pad_name
      %{^child => {Membrane.Bin, :itself}} -> Pad.opposite_direction(direction)
      _ -> direction
    end
  end
end
