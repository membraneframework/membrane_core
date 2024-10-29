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
    pad_opts = Keyword.get(specs, :options, [])
    {escaped_pad_opts, pad_opts_typedef} = OptionsSpecs.def_pad_options(pad_name, pad_opts)

    specs = Keyword.put(specs, :options, escaped_pad_opts)
    {accepted_format, specs} = Keyword.pop!(specs, :accepted_format)

    accepted_formats =
      case accepted_format do
        {:any_of, _meta, args} -> args
        other -> [other]
      end

    for format <- accepted_formats do
      with :any <- format do
        Membrane.Logger.warning("""
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
    :ok = warn_on_multiple_auto_input_and_output_pads(pads, env)

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

  @spec warn_on_multiple_auto_input_and_output_pads(
          pads :: [{Pad.name(), Pad.description()}],
          env :: Macro.Env.t()
        ) :: :ok
  defp warn_on_multiple_auto_input_and_output_pads(pads, env) do
    {auto_input_pads, auto_output_pads} =
      pads
      |> Enum.filter(fn {_pad, info} -> info[:flow_control] == :auto end)
      |> Enum.split_with(fn {_pad, info} -> info.direction == :input end)

    if length(auto_input_pads) >= 2 and length(auto_output_pads) >= 2 do
      IO.warn("""
      #{inspect(env.module)} defines multiple input pads with `flow_control: :auto` and multiple output \
      pads with `flow_control: :auto` at the same time. Notice, that lack of demand on any of output pads \
      with `flow_control: :auto` will cause stoping demand on every input pad with `flow_control: :auto`.
      Input pads with `flow_control: :auto`: #{auto_input_pads |> Keyword.keys() |> Enum.join(", ")}.
      Output pads with `flow_control: :auto`: #{auto_output_pads |> Keyword.keys() |> Enum.join(", ")}.
      """)
    end

    :ok
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
                flow_control: fn _config ->
                  cond do
                    component == :bin ->
                      nil

                    direction == :output and component != :filter ->
                      [in: [:manual, :push]]

                    direction == :input or component == :filter ->
                      [in: [:auto, :manual, :push], default: :auto]
                  end
                end,
                demand_unit:
                  &cond do
                    component == :bin or &1[:flow_control] != :manual ->
                      nil

                    direction == :input ->
                      [in: [:buffers, :bytes]]

                    direction == :output ->
                      [in: [:buffers, :bytes, nil], default: nil]

                    true ->
                      nil
                  end,
                options: [default: nil]
              ) do
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
      case config.options do
        [] ->
          quote_expr("")

        options ->
          quote do
            """
            Pad options:

            #{unquote(OptionsSpecs.generate_opts_doc(options))}
            """
          end
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
