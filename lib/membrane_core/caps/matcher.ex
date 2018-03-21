defmodule Membrane.Caps.Matcher do
  import Kernel, except: [match?: 2]
  require Record

  alias Membrane.Helper

  @type caps_spec_t :: module() | {module(), keyword()}
  @type caps_specs_t :: :any | caps_spec_t() | [caps_spec_t()]

  Record.defrecordp(:range_t, __MODULE__.Range, min: 0, max: :infinity)
  Record.defrecordp(:in_t, __MODULE__.In, list: [])

  def range(min, max) do
    range_t(min: min, max: max)
  end

  def one_of(values) when is_list(values) do
    in_t(list: values)
  end

  @doc """
  Function used to make sure caps specs are valid.

  In particular, valid caps:

  * Have shape described by caps_specs_t() type
  * If they contain keyword list, the keys are present in requested caps type

  It returns :ok when caps are valid and {:error, reason} otherwise
  """
  @spec validate_specs(caps_specs_t() | any()) :: :ok | {:error, reason :: tuple()}
  def validate_specs(specs_list) when is_list(specs_list) do
    specs_list |> Helper.Enum.each_with(&validate_specs/1)
  end

  def validate_specs({type, keyword_specs}) do
    caps = type.__struct__
    caps_keys = caps |> Map.from_struct() |> Map.keys() |> MapSet.new()
    spec_keys = keyword_specs |> Keyword.keys() |> MapSet.new()

    if MapSet.subset?(spec_keys, caps_keys) do
      :ok
    else
      invalid_keys = MapSet.difference(spec_keys, caps_keys) |> MapSet.to_list()
      {:error, {:invalid_keys, type, invalid_keys}}
    end
  end

  def validate_specs(specs) when is_atom(specs), do: :ok
  def validate_specs(specs), do: {:error, {:invalid_specs, specs}}

  @doc """
  Function determining whether the caps match provided specs.

  When :any is used as specs, caps can by anything (i.e. they can be invalid)
  """
  @spec match?(:any, any()) :: true
  @spec match?(caps_specs_t(), struct()) :: boolean()
  def match?(:any, _), do: true

  def match?(specs, %_{} = caps) when is_list(specs) do
    specs |> Enum.any?(fn spec -> match?(spec, caps) end)
  end

  def match?({type, keyword_specs}, %caps_type{} = caps) do
    type == caps_type && keyword_specs |> Enum.all?(fn kv -> kv |> match_caps_entry(caps) end)
  end

  def match?(type, %caps_type{}) when is_atom(type) do
    type == caps_type
  end

  defp match_caps_entry({spec_key, spec_value}, %{} = caps) do
    {:ok, caps_value} = caps |> Map.fetch(spec_key)
    match_value(spec_value, caps_value)
  end

  defp match_value(in_t(list: specs), value) when is_list(specs) do
    specs |> Enum.any?(fn spec -> match_value(spec, value) end)
  end

  defp match_value(range_t(min: min, max: max), value) do
    min <= value && value <= max
  end

  defp match_value(spec, value) do
    spec == value
  end
end
