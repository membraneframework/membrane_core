defmodule Membrane.Element.Manager.CapsMatcher do
  def validate_specs!({type, keyword_specs}) do
    caps = type.__struct__
    caps_keys = caps |> Map.from_struct() |> Map.keys() |> MapSet.new()
    spec_keys = keyword_specs |> Keyword.keys() |> MapSet.new()

    if MapSet.subset?(spec_keys, caps_keys) do
      :ok
    else
      invalid_keys = MapSet.difference(spec_keys, caps_keys)
      raise(ArgumentError, "Specs include invalid keys: #{inspect(invalid_keys)}")
    end
  end

  def validate_specs!({_type}), do: :ok
  def validate_specs!(:any), do: :ok
  def validate_specs!(specs), do: raise(ArgumentError, "Invalid specs #{inspect(specs)}")

  def match(:any, _), do: true

  def match(specs, %_{} = caps) when is_list(specs) do
    specs |> Enum.any?(fn spec -> match(spec, caps) end)
  end

  def match({type, keyword_specs}, %caps_type{} = caps) do
    type == caps_type && keyword_specs |> Enum.all?(fn kv -> kv |> match_caps_entry(caps) end)
  end

  def match({type}, %caps_type{}) do
    type == caps_type
  end

  def match(_, _), do: raise(ArgumentError)

  defp match_caps_entry({spec_key, spec_value}, %{} = caps) do
    with {:ok, caps_value} <- caps |> Map.fetch(spec_key) do
      match_value(spec_value, caps_value)
    else
      _ -> false
    end
  end

  defp match_value(spec, value) when is_list(spec) do
    value in spec
  end

  defp match_value({min, max}, value) do
    min <= value && value <= max
  end

  defp match_value(spec, value) do
    spec == value
  end
end
