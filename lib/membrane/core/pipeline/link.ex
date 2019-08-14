defmodule Membrane.Core.Link do
  @moduledoc false

  alias Membrane.Core.Pad
  alias Membrane.Pipeline
  alias __MODULE__.Endpoint
  require Pad

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
    alias Membrane.Core.Pad
    alias Membrane.Pipeline

    @enforce_keys [:element, :pad_name]
    defstruct element: nil, pad_name: nil, id: nil, pad_ref: nil, pid: nil, opts: []

    @valid_opt_keys [:pad, :buffer]

    @type t() :: %__MODULE__{
            element: Element.name_t(),
            pad_name: Pad.name_t(),
            id: Pad.dynamic_id_t() | nil,
            pad_ref: Pad.ref_t() | nil,
            pid: pid() | nil,
            opts: Pipeline.Spec.endpoint_options_t()
          }

    @type resolved_t() :: %__MODULE__{
            element: Element.name_t(),
            pad_name: Pad.name_t(),
            id: Pad.dynamic_id_t() | nil,
            pad_ref: Pad.ref_t(),
            pid: pid(),
            opts: Pipeline.Spec.endpoint_options_t()
          }

    @spec parse(Pipeline.Spec.link_endpoint_spec_t() | any()) :: {:ok, t()} | {:error, any()}
    def parse({elem, pad_name}) do
      parse({elem, pad_name, nil, []})
    end

    def parse({elem, pad_name, opts}) when is_list(opts) do
      parse({elem, pad_name, nil, opts})
    end

    def parse({elem, pad_name, id}) when not is_list(id) do
      parse({elem, pad_name, id, []})
    end

    def parse({elem, pad_name, id, opts}) when is_list(opts) do
      with :ok <- validate_pad_name(pad_name),
           :ok <- validate_opts(opts) do
        {:ok, %__MODULE__{element: elem, pad_name: pad_name, id: id, opts: opts}}
      end
    end

    def parse(endpoint) do
      {:error, {:invalid_endpoint, endpoint}}
    end

    defp validate_pad_name(pad) when Pad.is_pad_name(pad), do: :ok
    defp validate_pad_name(pad), do: {:error, {:invalid_pad_format, pad}}

    defp validate_opts(opts) do
      if Keyword.keyword?(opts) do
        opts
        |> Keyword.keys()
        |> Bunch.Enum.try_each(fn
          key when key in @valid_opt_keys -> :ok
          invalid_key -> {:error, {:invalid_opts_key, invalid_key}}
        end)
      else
        {:error, {:invalid_opts, opts}}
      end
    end
  end

  @spec parse(Pipeline.Spec.links_spec_t()) :: {:ok, t()} | {:error, any()}
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
