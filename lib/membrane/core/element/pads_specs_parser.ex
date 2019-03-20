defmodule Membrane.Core.Element.PadsSpecsParser do
  @moduledoc false
  # Functions parsing element pads specifications, generating functions and docs
  # based on them.
  alias Membrane.{Caps, Element}
  alias Membrane.Core.Element.OptionsSpecParser
  alias Element.Pad
  alias Bunch.Type
  use Bunch

  @spec def_pads([{Pad.name_t(), raw_spec :: Macro.t()}], Pad.direction_t()) :: Macro.t()
  def def_pads(pads, direction) do
    pads
    |> Enum.reduce(
      quote do
      end,
      fn {name, spec}, acc ->
        pad_def = def_pad(name, direction, spec)

        quote do
          unquote(acc)
          unquote(pad_def)
        end
      end
    )
  end

  @spec def_pad_docs(Pad.direction_t()) :: String.t()
  def def_pad_docs(direction) do
    dir_str = direction |> to_string()

    """
    Macro that defines #{dir_str} pad for the element.

    Allows to use `one_of/1` and `range/2` functions from `Membrane.Caps.Matcher`
    without module prefix.

    It automatically generates documentation from the given definition
    and adds compile-time caps specs validation.

    The type `t:Membrane.Element.Pad.#{dir_str}_spec_t/0` describes how the definition of pads should look.
    """
  end

  @spec def_pad(Pad.name_t(), Pad.direction_t(), Macro.t()) :: Macro.t()
  def def_pad(pad_name, direction, raw_specs) do
    Code.ensure_loaded(Caps.Matcher)

    specs =
      raw_specs
      |> Bunch.Macro.inject_calls([
        {Caps.Matcher, :one_of},
        {Caps.Matcher, :range}
      ])

    {pad_opts_type_name, pad_opts_typedef, pad_opts_parser_fun} =
      OptionsSpecParser.def_pad_options(pad_name, specs[:options])

    nspecs = specs |> Keyword.put(:options, pad_opts_type_name)

    quote do
      if Module.get_attribute(__MODULE__, :membrane_pad) == nil do
        Module.register_attribute(__MODULE__, :membrane_pad, accumulate: true)
        Module.register_attribute(__MODULE__, :membrane_pad_opts_parser_clauses, accumulate: true)
        @before_compile {unquote(__MODULE__), :generate_membrane_pads}
      end

      @membrane_pad unquote(__MODULE__).parse_pad_specs!(
                      {unquote(pad_name), unquote(nspecs)},
                      unquote(direction),
                      __ENV__
                    )
      @membrane_pad_opts_parser_clauses Macro.escape(unquote(pad_opts_parser_fun))
      unquote(pad_opts_typedef)
    end
  end

  # Generates `membrane_pads/0` function, along with docs and typespecs.
  defmacro generate_membrane_pads(env) do
    :ok = validate_pads!(Module.get_attribute(env.module, :membrane_pad), env)

    alias Membrane.Element.Pad

    pad_opts_parser_fun =
      env.module
      |> Module.get_attribute(:membrane_pad_opts_parser_clauses)
      |> Enum.reduce(
        quote do
        end,
        fn new_clause, acc ->
          quote do
            unquote(acc)
            unquote(new_clause)
          end
        end
      )

    quote do
      @doc """
      Returns pads descriptions for `#{inspect(__MODULE__)}`
      """
      @spec membrane_pads() :: [{unquote(Pad).name_t(), unquote(Pad).description_t()}]
      def membrane_pads() do
        @membrane_pad
      end

      unquote(pad_opts_parser_fun)

      @moduledoc """
      #{@moduledoc}

      ## Pads

      #{@membrane_pad |> unquote(__MODULE__).generate_docs_from_pads_specs()}
      """
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
          declaration_env :: Macro.Env.t()
        ) :: {Pad.name_t(), Pad.description_t()}
  def parse_pad_specs!(specs, direction, env) do
    with {:ok, specs} <- parse_pad_specs(specs, direction) do
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

  @spec parse_pad_specs(Pad.spec_t(), Pad.direction_t()) ::
          Type.try_t({Pad.name_t(), Pad.description_t()})
  def parse_pad_specs(spec, direction) do
    withl spec: {name, config} when is_atom(name) and is_list(config) <- spec,
          config:
            {:ok, config} <-
              config
              |> Bunch.Config.parse(
                availability: [in: [:always, :on_request], default: :always],
                caps: [validate: &Caps.Matcher.validate_specs/1],
                mode: [in: [:pull, :push], default: :pull],
                demand_unit: [
                  in: [:buffers, :bytes],
                  require_if: &(&1.mode == :pull and direction == :input)
                ],
                options: [default: nil]
              ) do
      {:ok, {name, Map.put(config, :direction, direction)}}
    else
      spec: spec -> {:error, {:invalid_pad_spec, spec}}
      config: {:error, reason} -> {:error, {reason, pad: name}}
    end
  end

  # Generates docs describing pads, based on pads specification.
  @spec generate_docs_from_pads_specs(Pad.description_t()) :: String.t()
  def generate_docs_from_pads_specs(pads_specs) do
    pads_specs
    |> Enum.map(&generate_docs_from_pad_specs/1)
    |> Enum.join("\n")
  end

  defp generate_docs_from_pad_specs({name, config}) do
    {pad_opts, config} = config |> Map.pop(:options)

    pad_doc = """
    ### `#{inspect(name)}`
    #{
      config
      |> Enum.filter(fn {_, v} -> v end)
      |> Enum.map(fn {k, v} ->
        {
          k |> to_string() |> String.replace("_", "&nbsp;"),
          generate_pad_property_doc(k, v)
        }
      end)
      |> Enum.map_join("\n", fn {k, v} ->
        "#{k} | #{v}"
      end)
    }
    """

    options_doc =
      if pad_opts do
        """
        #{Bunch.Markdown.hard_indent("Options", 4)}

        #{pad_opts}
        """
      else
        ""
      end

    pad_doc <> options_doc
  end

  defp generate_pad_property_doc(:caps, caps) do
    caps
    |> Bunch.listify()
    |> Enum.map(fn
      {module, params} ->
        params_doc =
          params
          |> Enum.map(fn {k, v} -> Bunch.Markdown.hard_indent("`#{k}: #{inspect(v)}`") end)
          |> Enum.join(",<br />")

        "`#{inspect(module)}`, restrictions:<br />#{params_doc}"

      module ->
        "`#{inspect(module)}`"
    end)
    ~> (
      [doc] -> doc
      docs -> docs |> Enum.join(",<br />")
    )
  end

  defp generate_pad_property_doc(:options, name) do
    "see `t:#{to_string(name)}/0`"
  end

  defp generate_pad_property_doc(_k, v) do
    "`#{inspect(v)}`"
  end
end
