defmodule Membrane.Caps.Matcher do
  @moduledoc """
  Module that allows to specify allowed caps and verify that they match specification.

  Caps specifications (specs) should be in one of the formats:

    * simply module name of the desired caps (e.g. `Membrane.Caps.Audio.Raw` or `Raw` with proper alias)
    * tuple with module name and keyword list of specs for specific caps fields (e.g. `{Raw, format: :s24le}`)
    * list of the formats described above

  Field values can be specified in following ways:

    * By a raw value for the field (e.g. `:s24le`)
    * Using `range/2` for values comparable with `Kernel.<=/2` and `Kernel.>=/2` (e.g. `Matcher.range(0, 255)`)
    * With `one_of/1` and a list of valid values (e.g `Matcher.one_of([:u8, :s16le, :s32le])`)
      Checks on the values from list are performed recursivly i.e. it can contain another `range/2`,
      for example `Matcher.one_of([0, Matcher.range(2, 4), Matcher.range(10, 20)])`

  If the specs are defined inside of `Membrane.Element.Base.Mixin.SinkBehaviour.def_known_sink_pads/1` and
  `Membrane.Element.Base.Mixin.SourceBehaviour.def_known_source_pads/1` module name can be ommitted from
  `range/2` and `one_of/1` calls.
  """
  import Kernel, except: [match?: 2]
  require Record

  alias Membrane.Helper

  @type caps_spec_t :: module() | {module(), keyword()}
  @type caps_specs_t :: :any | caps_spec_t() | [caps_spec_t()]

  @opaque range_spec_t :: record(:range_t, min: any, max: any)
  Record.defrecordp(:range_t, __MODULE__.Range, min: 0, max: :infinity)

  @opaque list_spec_t :: record(:in_t, list: list())
  Record.defrecordp(:in_t, __MODULE__.In, list: [])

  @doc """
  Returns opaque `t:range_spec_t/0` that specifies range of valid values for caps field
  """
  @spec range(any, any) :: range_spec_t
  def range(min, max) do
    range_t(min: min, max: max)
  end

  @doc """
  Returns opaque `t:list_spec_t/0` that specifies list of valid values for caps field
  """
  @spec one_of(list()) :: list_spec_t
  def one_of(values) when is_list(values) do
    in_t(list: values)
  end

  @doc """
  Function used to make sure caps specs are valid.

  In particular, valid caps:

    * Have shape described by `t:caps_specs_t/0` type
    * If they contain keyword list, the keys are present in requested caps type

  It returns `:ok` when caps are valid and `{:error, reason}` otherwise
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
      invalid_keys = spec_keys |> MapSet.difference(caps_keys) |> MapSet.to_list()
      {:error, {:invalid_keys, type, invalid_keys}}
    end
  end

  def validate_specs(specs) when is_atom(specs), do: :ok
  def validate_specs(specs), do: {:error, {:invalid_specs, specs}}

  @doc """
  Function determining whether the caps match provided specs.

  When `:any` is used as specs, caps can by anything (i.e. they can be invalid)
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
