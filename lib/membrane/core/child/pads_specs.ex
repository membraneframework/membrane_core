defmodule Membrane.Core.Child.PadsSpecs do
  @moduledoc false
  # Functions parsing element and bin pads specifications, generating functions and docs
  # based on them.
  use Bunch

  alias Membrane.Core.OptionsSpecs
  alias Membrane.Pad

  require Pad

  @doc """
  Returns documentation string common for both input and output pads
  """
  @spec def_pad_docs(Pad.direction_t(), :bin | :element) :: String.t()
  def def_pad_docs(direction, component) do
    {entity, pad_type_spec} =
      case component do
        :bin -> {"bin", "bin_spec_t/0"}
        :element -> {"element", "#{direction}_spec_t/0"}
      end

    """
    Macro that defines #{direction} pad for the #{entity}.

    It automatically generates documentation from the given definition
    and adds compile-time caps specs validation.

    The type `t:Membrane.Pad.#{pad_type_spec}` describes how the definition of pads should look.
    """
  end

  @doc """
  Returns AST inserted into element's or bin's module defining a pad
  """
  @spec def_pad(Pad.name_t(), Pad.direction_t(), Macro.t(), :element | :bin) :: Macro.t()
  def def_pad(pad_name, direction, specs, component) do
    {escaped_pad_opts, pad_opts_typedef} = OptionsSpecs.def_pad_options(pad_name, specs[:options])

    specs = Keyword.put(specs, :options, escaped_pad_opts)
    {caps_pattern, specs} = Keyword.pop!(specs, :caps)
    specs = [{:caps_pattern, Macro.to_string(caps_pattern)} | specs]

    case_statement_clauses =
      Bunch.listify(caps_pattern)
      |> Enum.map(fn
        {:__aliases__, _meta, _module} = ast -> quote do: %unquote(ast){}
        ast when is_atom(ast) -> quote do: %unquote(ast){}
        ast -> ast
      end)
      |> Enum.flat_map(fn pattern ->
        quote do
          unquote(pattern) -> true
        end
      end)
      |> Enum.concat(
        quote generated: true do
          _else -> false
        end
      )

    quote do
      unquote(do_ensure_default_membrane_pads())

      @membrane_pads unquote(__MODULE__).parse_pad_specs!(
                       {unquote(pad_name), unquote(specs)},
                       unquote(direction),
                       unquote(component),
                       __ENV__
                     )
      unquote(pad_opts_typedef)

      unless Module.defines?(__MODULE__, {:membrane_caps_match?, 2}) do
        @doc false
        @spec membrane_caps_match?(Membrane.Pad.name_t(), Membrane.Caps.t()) :: boolean()
      end

      def membrane_caps_match?(unquote(pad_name), caps) do
        case caps, do: unquote(case_statement_clauses)
      end
    end
  end

  defmacro ensure_default_membrane_pads() do
    do_ensure_default_membrane_pads()
  end

  defp do_ensure_default_membrane_pads() do
    quote do
      if Module.get_attribute(__MODULE__, :membrane_pads) == nil do
        Module.register_attribute(__MODULE__, :membrane_pads, accumulate: true)
        @before_compile {unquote(__MODULE__), :generate_membrane_pads}
      end
    end
  end

  @doc """
  Generates `membrane_pads/0` function, along with docs and typespecs.
  """
  defmacro generate_membrane_pads(env) do
    pads = Module.get_attribute(env.module, :membrane_pads, []) |> Enum.reverse()
    :ok = validate_pads!(pads, env)

    alias Membrane.Pad

    quote do
      @doc """
      Returns pads descriptions for `#{inspect(__MODULE__)}`
      """
      @spec membrane_pads() :: [{unquote(Pad).name_t(), unquote(Pad).description_t()}]
      def membrane_pads() do
        unquote(pads |> Macro.escape())
      end
    end
  end

  @spec validate_pads!(
          pads :: [{Pad.name_t(), Pad.description_t()}],
          env :: Macro.Env.t()
        ) :: :ok
  defp validate_pads!(pads, env) do
    with [] <- pads |> Keyword.keys() |> Bunch.Enum.duplicates() do
      :ok
    else
      dups ->
        raise CompileError, file: env.file, description: "Duplicate pad names: #{inspect(dups)}"
    end
  end

  @spec parse_pad_specs!(
          specs :: Pad.spec_t(),
          direction :: Pad.direction_t(),
          :element | :bin,
          declaration_env :: Macro.Env.t()
        ) :: {Pad.name_t(), Pad.description_t()}
  def parse_pad_specs!(specs, direction, component, env) do
    with {:ok, specs} <- parse_pad_specs(specs, direction, component) do
      specs
    else
      {:error, reason} ->
        raise CompileError,
          file: env.file,
          line: env.line,
          description: """
          Error parsing pad specs defined in #{inspect(env.module)}.def_#{direction}_pads/1,
          reason: #{inspect(reason)}
          """
    end
  end

  @spec parse_pad_specs(Pad.spec_t(), Pad.direction_t(), :element | :bin) ::
          {Pad.name_t(), Pad.description_t()} | {:error, reason :: any}
  def parse_pad_specs(spec, direction, component) do
    withl spec: {name, config} when Pad.is_pad_name(name) and is_list(config) <- spec,
          config:
            {:ok, config} <-
              config
              |> Bunch.Config.parse(
                availability: [in: [:always, :on_request], default: :always],
                caps_pattern: [default: nil],
                mode: [in: [:pull, :push], default: :pull],
                demand_mode: [
                  in: [:auto, :manual],
                  default: :manual
                ],
                demand_unit: [
                  in: [:buffers, :bytes],
                  require_if:
                    &(&1.mode == :pull and &1.demand_mode != :auto and
                        (component == :bin or direction == :input)),
                  default: :buffers
                ],
                options: [default: nil]
              ) do
      config = if component == :bin, do: Map.delete(config, :demand_mode), else: config

      config
      |> Map.put(:direction, direction)
      |> Map.put(:name, name)
      ~> {:ok, {name, &1}}
    else
      spec: spec -> {:error, {:invalid_pad_spec, spec}}
      config: {:error, reason} -> {:error, {reason, pad: name}}
    end
  end

  @doc """
  Generates docs describing pads based on pads specification.
  """
  @spec generate_docs_from_pads_specs([{Pad.name_t(), Pad.description_t()}]) :: Macro.t()
  def generate_docs_from_pads_specs([]) do
    quote do
      """
      There are no pads.
      """
    end
  end

  def generate_docs_from_pads_specs(pads_specs) do
    pads_docs =
      pads_specs
      |> Enum.sort_by(fn {_, config} -> config[:direction] end)
      |> Enum.map(&generate_docs_from_pad_specs/1)
      |> Enum.reduce(fn x, acc ->
        quote do
          """
          #{unquote(acc)}
          #{unquote(x)}
          """
        end
      end)

    quote do
      """
      ## Pads

      #{unquote(pads_docs)}
      """
    end
  end

  defp generate_docs_from_pad_specs({name, config}) do
    {pad_opts, config} = config |> Map.pop(:options)

    config_doc =
      config
      |> Enum.map(fn {k, v} ->
        {
          k |> to_string() |> String.replace("_", " ") |> String.capitalize(),
          generate_pad_property_doc(k, v)
        }
      end)
      |> Enum.map_join("\n", fn {k, v} ->
        "<tr><td>#{k}</td> <td>#{v}</td></tr>"
      end)

    options_doc =
      if pad_opts != nil do
        quote do
          """
          #{Bunch.Markdown.indent("Options:")}

          #{unquote(OptionsSpecs.generate_opts_doc(pad_opts))}
          """
        end
      else
        quote_expr("")
      end

    quote do
      """
      ### `#{inspect(unquote(name))}`

      <table>
      #{unquote(config_doc)}
      </table>
      """ <> unquote(options_doc)
    end
  end

  defp generate_pad_property_doc(:caps_pattern, pattern_string) when is_binary(pattern_string) do
    "<code>#{pattern_string}</code>"
  end

  defp generate_pad_property_doc(_k, v) do
    "<code>#{inspect(v)}</code>"
  end
end
