defmodule Membrane.Pipeline.Link do
  @moduledoc false

  alias Membrane.Element.Pad
  require Pad

  @enforce_keys [:from, :to]
  defstruct @enforce_keys

  @type t() :: %__MODULE__{from: Endpoint.t(), to: Endpoint.t()}

  @typep resolved_t :: %__MODULE__{
           from: Endpoint.resolved_t(),
           to: Endpoint.resolved_t()
         }

  defmodule Endpoint do
    @moduledoc false

    alias Membrane.Element
    alias Membrane.Element.Pad

    @enforce_keys [:element, :pad_name]
    defstruct element: nil, pad_name: nil, pad_ref: nil, pid: nil, opts: []

    @type t() :: %__MODULE__{
            element: Element.name_t(),
            pad_name: Pad.name_t(),
            pad_ref: Pad.ref_t() | nil,
            pid: pid() | nil,
            opts: keyword()
          }

    @type resolved_t() :: %__MODULE__{
            element: Element.name_t(),
            pad_name: Pad.name_t(),
            pad_ref: Pad.ref_t(),
            pid: pid(),
            opts: keyword()
          }

    @spec parse(Pipeline.link_spec_t() | any()) :: {:ok, t()} | {:error, any()}
    def parse({elem, pad_name}) do
      %__MODULE__{element: elem, pad_name: pad_name, opts: []} |> validate()
    end

    def parse({elem, pad_name, opts}) when is_list(opts) do
      %__MODULE__{element: elem, pad_name: pad_name, opts: opts} |> validate()
    end

    def parse(endpoint) do
      {:error, {:invalid_endpoint, endpoint}}
    end

    defp validate(%__MODULE__{pad_name: pad} = endpoint) do
      if Pad.is_pad_name(pad) do
        {:ok, endpoint}
      else
        {:error, {:invalid_pad_format, pad}}
      end
    end
  end

  @spec parse(Pipeline.links_spec_t() | any()) :: {:ok, t()} | {:error, any()}
  def parse({from, to}) do
    with {:ok, from} <- Endpoint.parse(from),
         {:ok, to} <- Endpoint.parse(to) do
      {:ok, %__MODULE__{from: from, to: to}}
    end
  end

  def parse(link) do
    {:error, {:invalid_link, link}}
  end
end
