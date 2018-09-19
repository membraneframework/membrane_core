defmodule Membrane.Core.Element.PadsSpecsParser do
  @moduledoc """
  Functions parsing element pads specifications, generating functions and docs
  based on them.
  """
  alias Membrane.{Buffer, Caps, Element}
  alias Element.Pad
  alias Bunch.Type
  use Bunch

  @type parsed_pad_specs_t :: %{
          availability: Pad.availability_t(),
          mode: Pad.mode_t(),
          caps: Caps.Matcher.caps_specs_t(),
          demand_in: Buffer.Metric.unit_t()
        }

  @doc """
  Generates `membrane_{direction}_pads/0` function, along with docs and typespecs.

  Pads specifications are parsed with `parse_pads_specs!/4`, and docs are
  generated with `generate_docs_from_pads_specs/1`.
  """
  @spec def_pads(Macro.t(), Pad.direction_t()) :: Macro.t()
  def def_pads(raw_specs, direction) do
    Code.ensure_loaded(Caps.Matcher)

    specs =
      raw_specs
      |> Bunch.Macro.inject_calls([
        {Caps.Matcher, :one_of},
        {Caps.Matcher, :range}
      ])

    quote do
      already_parsed = __MODULE__ |> Module.get_attribute(:membrane_pads) || []

      @membrane_pads unquote(specs)
                     |> unquote(__MODULE__).parse_pads_specs!(
                       already_parsed,
                       unquote(direction),
                       __ENV__
                     )
                     |> Kernel.++(already_parsed)

      @doc """
      Returns pads specification for `#{inspect(__MODULE__)}`

      They are the following:
        #{@membrane_pads |> unquote(__MODULE__).generate_docs_from_pads_specs()}
      """
      if __MODULE__ |> Module.defines?({:membrane_pads, 0}) do
        __MODULE__ |> Module.make_overridable(membrane_pads: 0)
      else
        @spec membrane_pads() :: [Membrane.Element.pad_specs_t()]
      end

      @impl true
      def membrane_pads() do
        @membrane_pads
      end
    end
  end

  @doc """
  Parses pads specifications defined with `Membrane.Element.Base.Mixin.SourceBehaviour.def_source_pads/1`
  or `Membrane.Element.Base.Mixin.SinkBehaviour.def_sink_pads/1`.
  """
  @spec parse_pads_specs!(
          specs :: [Element.pad_specs_t()],
          already_parsed :: [{Pad.name_t(), parsed_pad_specs_t}],
          direction :: Pad.direction_t(),
          declaration_env :: Macro.Env.t()
        ) :: parsed_pad_specs_t | no_return
  def parse_pads_specs!(specs, already_parsed, direction, env) do
    with {:ok, specs} <- parse_pads_specs(specs, already_parsed, direction) do
      specs
    else
      {:error, reason} ->
        raise CompileError,
          file: env.file,
          line: env.line,
          description: """
          Error parsing pads specs defined in #{inspect(env.module)}.def_#{direction}_pads/1,
          reason: #{inspect(reason)}
          """
    end
  end

  @spec parse_pads_specs(
          specs :: [Element.pad_specs_t()],
          already_parsed :: [{Pad.name_t(), parsed_pad_specs_t}],
          direction :: Pad.direction_t()
        ) :: Type.try_t(parsed_pad_specs_t)
  defp parse_pads_specs(specs, already_parsed, direction) do
    withl keyword: true <- specs |> Keyword.keyword?(),
          dups: [] <- (specs ++ already_parsed) |> Keyword.keys() |> Bunch.Enum.duplicates(),
          parse: {:ok, specs} <- specs |> Bunch.Enum.try_map(&parse_pad_specs(&1, direction)) do
      specs |> Bunch.TupleList.map_values(&Map.put(&1, :direction, direction)) ~> {:ok, &1}
    else
      keyword: false -> {:error, {:pads_not_a_keyword, specs}}
      dups: dups -> {:error, {:duplicate_pad_names, dups}}
      parse: {:error, reason} -> {:error, reason}
    end
  end

  defp parse_pad_specs(spec, direction) do
    withl spec: {name, config} when is_atom(name) and is_list(config) <- spec,
          config:
            {:ok, config} <-
              Bunch.Config.parse(config,
                availability: [in: [:always, :on_request], default: :always],
                caps: [validate: &Caps.Matcher.validate_specs/1],
                mode: [in: [:pull, :push], default: :pull],
                demand_in: [
                  in: [:buffers, :bytes],
                  require_if: &(&1.mode == :pull and direction == :sink)
                ]
              ) do
      {:ok, {name, config}}
    else
      spec: spec -> {:error, {:invalid_pad_spec, spec}}
      config: {:error, reason} -> {:error, {reason, pad: name}}
    end
  end

  @doc """
  Generates docs describing pads, based on pads specification.
  """
  @spec generate_docs_from_pads_specs(parsed_pad_specs_t) :: String.t()
  def generate_docs_from_pads_specs(pads_specs) do
    pads_specs
    |> Enum.map(&generate_docs_from_pad_specs/1)
    |> Enum.join("\n")
  end

  defp generate_docs_from_pad_specs({name, config}) do
    """
    * Pad `#{inspect(name)}`
    #{
      config
      |> Enum.map(fn {k, v} ->
        "* #{k |> to_string() |> String.replace("_", " ")}: #{generate_pad_property_doc(k, v)}"
      end)
      |> Enum.join("\n")
      |> indent(2)
    }
    """
  end

  defp generate_pad_property_doc(:caps, caps) do
    caps
    |> Bunch.listify()
    |> Enum.map(fn
      {module, params} ->
        params_doc =
          params |> Enum.map(fn {k, v} -> "`#{k}`:&nbsp;`#{inspect(v)}`" end) |> Enum.join(", ")

        "`#{inspect(module)}`, params: #{params_doc}"

      module ->
        "`#{inspect(module)}`"
    end)
    ~> (
      [doc] -> doc
      docs -> docs |> Enum.map(&"\n* #{&1}") |> Enum.join()
    )
    |> indent()
  end

  defp generate_pad_property_doc(_k, v) do
    "`#{inspect(v)}`"
  end

  defp indent(string, size \\ 1) do
    string
    |> String.split("\n")
    |> Enum.map(&(String.duplicate("  ", size) <> &1))
    |> Enum.join("\n")
  end
end
