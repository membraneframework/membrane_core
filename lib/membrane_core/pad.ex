defmodule Membrane.Pad do
  @type name_t           :: atom | String.t
  @type availability_t   :: :always
  @type potential_caps_t :: :any | [Membrane.Caps.t]
  @type potential_pads_t :: %{required(name_t) => {availability_t, potential_caps_t}}


  @doc """
  Checks if given list of potential caps are compatible.

  Returns `true` if they are compatible, `false` otherwise.
  """
  @spec compatible?(potential_caps_t, potential_caps_t) :: boolean
  def compatible?(:any, _caps2), do: true
  def compatible?(_caps1, :any), do: true
  def compatible?(caps1, caps2) when is_list(caps1) and is_list(caps2) do
    length(Membrane.Caps.intersect(caps1, caps2)) != 0
  end
end
