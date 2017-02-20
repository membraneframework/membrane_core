defmodule Membrane.Pad do
  @type name_t         :: atom | String.t
  @type availability_t :: :always
  @type known_caps_t   :: :any | [Membrane.Caps.t]
  @type known_pads_t   :: %{required(name_t) => {availability_t, known_caps_t}}


  # FIXME move to Caps
  @doc """
  Checks if given list of known caps are compatible.

  Returns `true` if they are compatible, `false` otherwise.
  """
  @spec compatible?(known_caps_t, known_caps_t) :: boolean
  def compatible?(:any, _caps2), do: true
  def compatible?(_caps1, :any), do: true
  def compatible?(caps1, caps2) when is_list(caps1) and is_list(caps2) do
    length(Membrane.Caps.intersect(caps1, caps2)) != 0
  end
end
