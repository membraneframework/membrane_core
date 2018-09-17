defmodule Membrane.Core.Element.PadsSpecsParser do
  @moduledoc """
  Functions parsing element pads specifications, generating functions and docs
  based on them.
  """
  alias Membrane.{Buffer, Caps, Element}
  alias Element.Pad
  use Bunch

  @type parsed_pad_specs_t :: %{
          availability: Pad.availability_t(),
          mode: Pad.Mode.t(),
          caps: Caps.Matcher.caps_specs_t(),
          demand_in: Buffer.unit_t()
        }

  @doc """
  Generates `membrane_{direction}_pads/0` function, along with docs and typespecs.

  Pads specifications are parsed with `parse_pads_specs!/3`, and docs are
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

    attr_name = fun_name = :"membrane_#{direction}_pads"
    spec_name = :"#{direction}_pad_specs_t"

    quote do
      Module.put_attribute(
        __MODULE__,
        unquote(attr_name),
        unquote(specs) |> unquote(__MODULE__).parse_pads_specs!(unquote(direction), __ENV__)
      )

      @doc """
      Returns #{unquote(direction)} pads specification for `#{inspect(__MODULE__)}`

      They are the following:
      #{
        unquote(specs)
        |> unquote(__MODULE__).parse_pads_specs!(unquote(direction), __ENV__)
        |> unquote(__MODULE__).generate_docs_from_pads_specs()
      }
      """
      @spec unquote(fun_name)() :: [Membrane.Element.unquote(spec_name)()]
      @impl true
      def unquote(fun_name)() do
        Kernel.@(unquote(Macro.var(attr_name, nil)))
      end
    end
  end

  @doc """
  Parses pads specifications defined with `Membrane.Element.Base.Mixin.SourceBehaviour.def_source_pads/1`
  or `Membrane.Element.Base.Mixin.SinkBehaviour.def_sink_pads/1`.
  """
  @spec parse_pads_specs!([Element.pad_specs_t()], Pad.direction_t(), Macro.Env.t()) ::
          parsed_pad_specs_t
  def parse_pads_specs!(specs, direction, env) do
    with true <- specs |> Keyword.keyword?() or {:error, {:pads_not_a_keyword, specs}},
         {:ok, specs} <- specs |> Bunch.Enum.try_map(&parse_pad_specs(&1, direction)) do
      specs |> Map.new()
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
  Generates docs describing pads, based no pads specification.
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
      |> indent()
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

  defp indent(string) do
    string |> String.split("\n") |> Enum.map(&"  #{&1}") |> Enum.join("\n")
  end
end
