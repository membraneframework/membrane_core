defmodule Membrane.Caps.Matcher do
  @moduledoc """
  Module that allows to specify valid caps and verify that they match specification.

  Caps specifications (specs) should be in one of the formats:

    * simply module name of the desired caps (e.g. `Membrane.Caps.Audio.Raw` or `Raw` with proper alias)
    * tuple with module name and keyword list of specs for specific caps fields (e.g. `{Raw, format: :s24le}`)
    * list of the formats described above

  Field values can be specified in following ways:

    * By a raw value for the field (e.g. `:s24le`)
    * Using `range/2` for values comparable with `Kernel.<=/2` and `Kernel.>=/2` (e.g. `Matcher.range(0, 255)`)
    * With `one_of/1` and a list of valid values (e.g `Matcher.one_of([:u8, :s16le, :s32le])`)
      Checks on the values from list are performed recursively i.e. it can contain another `range/2`,
      for example `Matcher.one_of([0, Matcher.range(2, 4), Matcher.range(10, 20)])`

  If the specs are defined inside of `Membrane.Element.WithInputPads.def_input_pad/2` and
  `Membrane.Element.WithOutputPads.def_output_pad/2` module name can be omitted from
  `range/2` and `one_of/1` calls.

  ## Example

  Below is a pad definition with an example of specs for caps matcher:

      alias Membrane.Caps.Video.Raw

      def_input_pad :input,
        demand_unit: :buffers,
        caps: {Raw, format: one_of([:I420, :I422]), aligned: true}

  """
  import Kernel, except: [match?: 2]

  alias Bunch

  require Record

  @type caps_spec_t :: module() | {module(), keyword()}
  @type caps_specs_t :: :any | caps_spec_t() | [caps_spec_t()]

  defmodule Range do
    @moduledoc false
    @enforce_keys [:min, :max]
    defstruct @enforce_keys
  end

  @opaque range_t :: %Range{min: any, max: any}

  defimpl Inspect, for: Range do
    import Inspect.Algebra

    @impl true
    def inspect(%Range{min: min, max: max}, opts) do
      concat(["range(", to_doc(min, opts), ", ", to_doc(max, opts), ")"])
    end
  end

  defmodule OneOf do
    @moduledoc false
    @enforce_keys [:list]
    defstruct @enforce_keys
  end

  @opaque one_of_t :: %OneOf{list: list()}

  defimpl Inspect, for: OneOf do
    import Inspect.Algebra

    @impl true
    def inspect(%OneOf{list: list}, opts) do
      concat(["one_of(", to_doc(list, opts), ")"])
    end
  end

  @doc """
  Returns opaque specification of range of valid values for caps field.
  """
  @spec range(any, any) :: range_t()
  def range(min, max) do
    %Range{min: min, max: max}
  end

  @doc """
  Returns opaque specification of list of valid values for caps field.
  """
  @spec one_of(list()) :: one_of_t()
  def one_of(values) when is_list(values) do
    %OneOf{list: values}
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
    specs_list |> Bunch.Enum.try_each(&validate_specs/1)
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
  @spec match?(caps_specs_t(), struct() | any()) :: boolean()
  def match?(:any, _caps), do: true

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

  defp match_value(%OneOf{list: specs}, value) when is_list(specs) do
    specs |> Enum.any?(fn spec -> match_value(spec, value) end)
  end

  defp match_value(%Range{min: min, max: max}, value) do
    min <= value && value <= max
  end

  defp match_value(spec, value) do
    spec == value
  end
end
