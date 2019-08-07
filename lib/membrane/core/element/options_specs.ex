defmodule Membrane.Core.Element.OptionsSpecs do
  @moduledoc false

  alias Membrane.Time
  alias Membrane.Core.Pad

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
    {opt_typespecs, escaped_opts} = parse_opts(options)
    typedoc = generate_opts_doc(escaped_opts)

    quote do
      @typedoc """
      Struct containing options for `#{inspect(__MODULE__)}`
      """
      @type t :: %unquote(module){unquote_splicing(opt_typespecs)}

      if @moduledoc != false do
        @moduledoc """
        #{@moduledoc}

        ## Element options

        Passed via struct `t:#{inspect(__MODULE__)}.t/0`

        #{unquote(typedoc)}
        """
      end

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

  @spec def_pad_options(Pad.name_t(), nil | Keyword.t()) :: {Macro.t(), Macro.t()}
  def def_pad_options(_pad_name, nil) do
    no_code =
      quote do
      end

    {nil, no_code}
  end

  def def_pad_options(pad_name, options) do
    {opt_typespecs, escaped_opts} = parse_opts(options)
    pad_opts_type_name = "#{pad_name}_pad_opts_t" |> String.to_atom()

    type_definiton =
      quote do
        @typedoc """
        Options for pad `#{inspect(unquote(pad_name))}`
        """
        @type unquote(Macro.var(pad_opts_type_name, nil)) :: unquote(opt_typespecs)
      end

    {escaped_opts, type_definiton}
  end

  def generate_opts_doc(escaped_opts) do
    escaped_opts
    |> Enum.map(&generate_opt_doc/1)
    |> Enum.reduce(fn opt_doc, acc ->
      quote do
        """
        #{unquote(acc)}

        #{unquote(opt_doc)}
        """
      end
    end)
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
        quote_expr("***Required***")
      end

    quote do
      """
      #{unquote(header)}

      #{unquote(default_val_desc) |> Bunch.Markdown.indent()}

      #{unquote(desc) |> String.trim() |> Bunch.Markdown.indent()}
      """
    end
  end

  defp parse_opts(kw) when is_list(kw) do
    # AST of typespec for keyword list containing options
    opt_typespecs =
      kw
      |> Bunch.KVList.map_values(fn v ->
        default_val = @default_types_params[v[:type]][:spec] || quote_expr(any)

        v[:spec] || default_val
      end)

    opts_without_typespecs = kw |> Bunch.KVList.map_values(&Keyword.delete(&1, :spec))

    {opt_typespecs, opts_without_typespecs}
  end
end
