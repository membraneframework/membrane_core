defmodule Membrane.Core.OptionsSpecs do
  @moduledoc false

  use Bunch

  alias Bunch.{KVEnum, Markdown}
  alias Membrane.Pad

  @spec options_doc() :: String.t()
  def options_doc do
    """
    Options are defined by a keyword list, where each key is an option name and
    is described by another keyword list with following fields:

      * `spec:` typespec for value in struct
      * `default:` default value for option. If not present, value for this option
        will have to be provided each time options struct is created
      * `inspector:` function converting fields' value to a string. Used when
        creating documentation instead of `inspect/1`, eg. `inspector: &Membrane.Time.inspect/1`
      * `description:` string describing an option. It will be used for generating the docs
    """
  end

  @spec def_options(module(), nil | Keyword.t(), :element | :bin) :: Macro.t()
  def def_options(module, options, child) do
    {opt_typespecs, escaped_opts} = parse_opts(options)
    typedoc = generate_opts_doc(escaped_opts)

    quote do
      @typedoc """
      Struct containing options for `#{inspect(__MODULE__)}`
      """
      @type t :: %unquote(module){unquote_splicing(opt_typespecs)}

      @membrane_options_moduledoc """
      ## #{unquote(child) |> to_string |> String.capitalize()} options

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

  @spec generate_opts_doc(escaped_opts :: Keyword.t()) :: Macro.t()
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
    header = "`#{Atom.to_string(opt_name)}`"

    spec = """
    ```
    #{Keyword.fetch!(opt_definition, :spec)}
    ```
    """

    default_value_doc =
      if Keyword.has_key?(opt_definition, :default) do
        inspector =
          opt_definition
          |> Keyword.get(
            :inspector,
            quote(do: &inspect/1)
          )

        quote do
          "Default value: `#{unquote(inspector).(unquote(opt_definition)[:default])}`"
        end
      else
        quote_expr("***Required***")
      end

    description = Keyword.get(opt_definition, :description, "")

    quote do
      description = unquote(description) |> String.trim()
      doc_parts = [unquote_splicing([spec, default_value_doc]), description]

      """
      - #{unquote(header)}  \n
      #{doc_parts |> Enum.map_join("  \n", &Markdown.indent/1)}
      """
    end
  end

  defp parse_opts(opts) when is_list(opts) do
    opts = KVEnum.map_values(opts, &Keyword.put_new(&1, :spec, quote_expr(any)))
    opts_typespecs = KVEnum.map_values(opts, & &1[:spec])

    escaped_opts =
      KVEnum.map_values(opts, fn definition ->
        Keyword.update!(definition, :spec, &Macro.to_string/1)
      end)

    {opts_typespecs, escaped_opts}
  end
end
