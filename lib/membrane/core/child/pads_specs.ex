defmodule Membrane.Core.Child.PadsSpecs do
  @moduledoc false
  # Functions parsing element and bin pads specifications, generating functions and docs
  # based on them.
  use Bunch

  alias Membrane.Core.OptionsSpecs
  alias Membrane.Pad

  require Membrane.Logger
  require Membrane.Pad

  @doc """
  Returns documentation string common for both input and output pads
  """
  @spec def_pad_docs(Pad.direction(), :bin | :element) :: String.t()
  def def_pad_docs(direction, component) do
    {entity, pad_type_spec} =
      case component do
        :bin -> {"bin", "bin_spec/0"}
        :element -> {"element", "element_spec/0"}
      end

    """
    Macro that defines #{direction} pad for the #{entity}.

    It automatically generates documentation from the given definition
    and adds compile-time stream format specs validation.

    The type `t:Membrane.Pad.#{pad_type_spec}` describes how the definition of pads should look.
    """
  end

  @doc """
  Returns AST inserted into element's or bin's module defining a pad
  """
  @spec def_pad(
          Pad.name(),
          Pad.direction(),
          Macro.t(),
          :filter | :endpoint | :source | :sink | :bin
        ) :: Macro.t()
  def def_pad(pad_name, direction, specs, component) do
    {escaped_pad_opts, pad_opts_typedef} = OptionsSpecs.def_pad_options(pad_name, specs[:options])

    specs = Keyword.put(specs, :options, escaped_pad_opts)
    {accepted_format, specs} = Keyword.pop!(specs, :accepted_format)

    accepted_formats =
      case accepted_format do
        {:any_of, _meta, args} -> args
        other -> [other]
      end

    for format <- accepted_formats do
      with :any <- format do
        Membrane.Logger.warn("""
        Remeber, that `accepted_format: :any` in pad definition will be satisified by stream format in form of %:any{}, \
        not >>any<< stream format (to achieve such an effect, put `accepted_format: _any` in your code)
        """)
      end
    end

    specs =
      accepted_formats
      |> Enum.map(&Macro.to_string/1)
      |> then(&[accepted_formats_str: &1])
      |> Enum.concat(specs)

    case_statement_clauses =
      accepted_formats
      |> Enum.map(fn
        {:__aliases__, _meta, _module} = ast -> quote do: %unquote(ast){}
        ast when is_atom(ast) -> quote do: %unquote(ast){}
        ast -> ast
      end)
      |> Enum.flat_map(fn ast ->
        quote do
          unquote(ast) -> true
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

      unless Module.defines?(__MODULE__, {:membrane_stream_format_match?, 2}) do
        @doc false
        @spec membrane_stream_format_match?(Membrane.Pad.name(), Membrane.StreamFormat.t()) ::
                boolean()
      end

      def membrane_stream_format_match?(unquote(pad_name), stream_format) do
        case stream_format, do: unquote(case_statement_clauses)
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
  Generates `membrane_pads/0` function.
  """
  defmacro generate_membrane_pads(env) do
    pads = Module.get_attribute(env.module, :membrane_pads, []) |> Enum.reverse()
    :ok = validate_pads!(pads, env)

    alias Membrane.Pad

    quote do
      @doc false
      @spec membrane_pads() :: [{unquote(Pad).name(), unquote(Pad).description()}]
      def membrane_pads() do
        unquote(pads |> Macro.escape())
      end
    end
  end

  @spec validate_pads!(
          pads :: [{Pad.name(), Pad.description()}],
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
          specs :: Pad.spec(),
          direction :: Pad.direction(),
          :filter | :endpoint | :source | :sink | :bin,
          declaration_env :: Macro.Env.t()
        ) :: {Pad.name(), Pad.description()}
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

  @spec parse_pad_specs(
          Pad.spec(),
          Pad.direction(),
          :filter | :endpoint | :source | :sink | :bin
        ) ::
          {Pad.name(), Pad.description()} | {:error, reason :: any}
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def parse_pad_specs(spec, direction, component) do
    withl spec: {name, config} when Pad.is_pad_name(name) and is_list(config) <- spec,
          config:
            {:ok, config} <-
              config
              |> Bunch.Config.parse(
                availability: [in: [:always, :on_request], default: :always],
                accepted_formats_str: [],
                options: [default: nil],
                demand_unit: [in: [:buffers, :bytes, nil], default: nil],
                flow_control: flow_control_parsing_options(config, direction, component),
                mode: mode_parsing_options(config, component),
                demand_mode: demand_mode_parsing_options(config, direction, component)
              ) do
      case config do
        _config when component == :bin ->
          config
          |> Map.delete(:demand_unit)

        %{mode: :push} ->
          config
          |> Map.drop([:mode, :demand_mode])
          |> Map.put(:flow_control, :push)

        %{mode: :pull, demand_mode: demand_mode} ->
          config
          |> Map.drop([:mode, :demand_mode])
          |> Map.put(:flow_control, demand_mode)

        %{flow_control: _flow_control} ->
          config
      end
      |> Map.merge(%{direction: direction, name: name})
      |> then(&{:ok, {name, &1}})
    else
      spec: spec -> {:error, {:invalid_pad_spec, spec}}
      config: {:error, reason} -> {:error, {reason, pad: name}}
    end
  end

  defp mode_parsing_options(config, component) do
    cond do
      component == :bin -> nil
      old_api?(config) -> [in: [:pull, :push], default: :pull]
      true -> nil
    end
  end

  defp demand_mode_parsing_options(config, direction, component) do
    cond do
      component == :bin or not old_api?(config) -> nil
      auto_allowed?(direction, component) -> [in: [:manual, :auto], default: :manual]
      true -> [in: [:manual], default: :manual]
    end
  end

  defp flow_control_parsing_options(config, direction, component) do
    cond do
      component == :bin or old_api?(config) -> nil
      auto_allowed?(direction, component) -> [in: [:auto, :manual, :push], default: :manual]
      true -> [in: [:manual, :push], default: :manual]
    end
  end

  defp old_api?(config) do
    Keyword.has_key?(config, :mode) or Keyword.has_key?(config, :demand_mode)
  end

  defp auto_allowed?(direction, component) do
    direction == :input or component == :filter
  end

  @doc """
  Generates docs describing pads based on pads specification.
  """
  @spec generate_docs_from_pads_specs([{Pad.name(), Pad.description()}]) :: Macro.t()
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
    config = config |> Map.delete(:name)

    accepted_formats_doc = """
    Accepted formats:
    #{Enum.map_join(config.accepted_formats_str, "\n", &"```\n#{&1}\n```")}
    """

    config_doc =
      [:direction, :availability, :flow_control, :demand_unit]
      |> Enum.filter(&Map.has_key?(config, &1))
      |> Enum.map_join("\n", &generate_pad_property_doc(&1, Map.fetch!(config, &1)))

    options_doc =
      if config.options do
        quote do
          """
          Pad options:

          #{unquote(OptionsSpecs.generate_opts_doc(config.options))}
          """
        end
      else
        quote_expr("")
      end

    quote do
      """
      ### `#{inspect(unquote(name))}`

      #{unquote(accepted_formats_doc)}
      #{unquote(config_doc)}
      #{unquote(options_doc)}
      """
    end
  end

  defp generate_pad_property_doc(property, value) do
    property_str = property |> to_string() |> String.replace("_", " ") |> String.capitalize()
    "#{property_str}: | `#{inspect(value)}`"
  end
end
