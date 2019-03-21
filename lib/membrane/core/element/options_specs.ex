defmodule Membrane.Core.Element.OptionsSpecs do
  @moduledoc false

  alias Membrane.Time
  alias Membrane.Element.Pad

  use Bunch

  @default_types_params %{
    atom: [spec: quote_expr(atom)],
    boolean: [spec: quote_expr(boolean)],
    string: [spec: quote_expr(String.t())],
    keyword: [spec: quote_expr(keyword)],
    struct: [spec: quote_expr(struct)],
    caps: [spec: quote_expr(struct)],
    time: [spec: quote_expr(Time.t()), inspector: &Time.to_code_str/1]
  }

  @spec options_doc() :: String.t()
  def options_doc do
    """
    Options are defined by a keyword list, where each key is an option name and
    is described by another keyword list with following fields:

      * `type:` atom, used for parsing
      * `spec:` typespec for value in struct. If ommitted, for types:
        `#{inspect(Map.keys(@default_types_params))}` the default typespec is provided,
        for others typespec is set to `t:any/0`
      * `default:` default value for option. If not present, value for this option
        will have to be provided each time options struct is created
      * `inspector:` function converting fields' value to a string. Used when
        creating documentation instead of `inspect/1`
      * `description:` string describing an option. It will be used for generating the docs
    """
  end

  @spec def_options(module(), nil | Keyword.t()) :: Macro.t()
  def def_options(module, options) do
    {typedoc, opt_typespecs, escaped_opts} = parse_opts(options)
    opt_typespec_ast = {:%{}, [], Keyword.put(opt_typespecs, :__struct__, module)}
    # opt_typespec_ast is equivalent of typespec %__CALLER__.module{key: value, ...}
    quote do
      @typedoc """
      Struct containing options for `#{inspect(__MODULE__)}`
      """
      @type t :: unquote(opt_typespec_ast)

      @moduledoc """
      #{@moduledoc}

      ## Element options

      Passed via struct `t:#{inspect(__MODULE__)}.t/0`

      #{unquote(typedoc)}
      """

      @doc """
      Returns description of options available for this module
      """
      @spec options() :: keyword
      def options(), do: unquote(escaped_opts)

      @enforce_keys unquote(escaped_opts)
                    |> Enum.reject(fn {k, v} -> v |> Keyword.has_key?(:default) end)
                    |> Keyword.keys()

      defstruct unquote(escaped_opts)
                |> Enum.map(fn {k, v} -> {k, v[:default]} end)
    end
  end

  @spec def_pad_options(Pad.name_t(), nil | Keyword.t()) :: {Macro.t(), Macro.t(), Macro.t()}
  def def_pad_options(pad_name, nil) do
    no_code =
      quote do
      end

    clauses =
      quote do
        @doc false
        def membrane_parse_pad_options(unquote(pad_name), nil) do
          {:ok, nil}
        end

        @doc false
        def membrane_parse_pad_options(unquote(pad_name), _) do
          {:error, {:options_not_defined, unquote(pad_name)}}
        end
      end

    {nil, no_code, clauses}
  end

  def def_pad_options(pad_name, options) do
    {typedoc, opt_typespecs, escaped_opts} = parse_opts(options)
    pad_opts_type_name = "#{pad_name}_pad_opts_t" |> String.to_atom()

    type_definiton =
      quote do
        @typedoc """
        Options for pad `#{inspect(unquote(pad_name))}`
        """
        @type unquote(Macro.var(pad_opts_type_name, nil)) :: unquote(opt_typespecs)
      end

    bunch_field_specs = escaped_opts |> Bunch.KVList.map_values(&Keyword.take(&1, [:default]))

    parser_fun_ast =
      quote do
        @doc false
        def membrane_parse_pad_options(unquote(pad_name), options) do
          options
          |> List.wrap()
          |> Bunch.Config.parse(unquote(bunch_field_specs))
        end
      end

    {typedoc, type_definiton, parser_fun_ast}
  end

  defp parse_opts(options) do
    {opt_typespecs, escaped_opts} = extract_typespecs(options)

    description =
      escaped_opts
      |> Enum.map(&generate_opt_doc(&1))
      |> Enum.reduce(fn x, acc ->
        quote do
          """
          #{unquote(x)}

          #{unquote(acc)}
          """
        end
      end)

    {description, opt_typespecs, escaped_opts}
  end

  defp generate_opt_doc({opt_name, opt_definition}) do
    header = "* `#{Atom.to_string(opt_name)}`"

    desc = opt_definition |> Keyword.get(:description, "")

    default_val_desc =
      if Keyword.has_key?(opt_definition, :default) do
        inspector =
          opt_definition
          |> Keyword.get(
            :inspector,
            @default_types_params[opt_definition[:type]][:inspector] || quote(do: &inspect/1)
          )

        quote do
          "Default value: `#{unquote(inspector).(unquote(opt_definition)[:default])}`"
        end
      else
        quote_expr("**Required**")
      end

    quote do
      """
      #{unquote(header)}

      #{unquote(default_val_desc) |> Bunch.Markdown.indent()}

      #{unquote(desc) |> String.trim() |> Bunch.Markdown.indent()}
      """
    end
  end

  defp extract_typespecs(kw) when is_list(kw) do
    with_default_specs =
      kw
      |> Enum.map(fn {k, v} ->
        default_val = @default_types_params[v[:type]][:spec] || quote_expr(any)

        {k, v |> Keyword.put_new(:spec, default_val)}
      end)

    # Actual AST with typespec for the option
    opt_typespecs =
      with_default_specs
      |> Enum.map(fn {k, v} -> {k, v[:spec]} end)

    # Options without typespec
    escaped_opts =
      with_default_specs
      |> Enum.map(fn {k, v} ->
        {k, v |> Keyword.put(:spec, Macro.to_string(v[:spec]))}
      end)

    {opt_typespecs, escaped_opts}
  end
end
