defmodule Membrane.Element.Manager.CapsMatcher do
  def match(specs, %_{} = caps) when is_list(specs) do
    specs |> Enum.any?(fn spec -> match(spec, caps) end)
  end

  def match(%{type: type} = spec, %_{} = caps) do
    type == caps.__struct__ && spec |> Map.delete(:type) |> match(caps)
  end

  def match(%{} = spec, %_{} = caps) do
    spec |> Enum.all?(fn {key, spec_value} -> match_value(spec_value, Map.get(caps, key)) end)
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
