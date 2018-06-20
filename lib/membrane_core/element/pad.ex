defmodule Membrane.Element.Pad do
  @moduledoc """
  Pads are units defined by each element, allowing it to be linked with another
  elements. This module consists of pads typespecs and utils.

  Each pad is described by its name, direction, availability, mode and possible caps.
  For pads to be linkable, these properties have to be compatible. For more
  information on each of them, check appropriate type in this module.

  Each link can only consist of exactly two pads.
  """

  use Membrane.Helper
  import Helper.Typespec

  @typedoc """
  Defines the term by which the pad is identified.
  """
  @type name_t :: atom | {:dynamic, atom, non_neg_integer}

  defguard is_pad_name(term)
           when term |> is_atom or
                  (term |> is_tuple and term |> tuple_size == 3 and term |> elem(0) == :dynamic and
                     term |> elem(1) |> is_atom and term |> elem(2) |> is_integer)

  @typedoc """
  Defines possible pad directions:
  - `:source` - data can only be sent through such pad,
  - `:sink` - data can only be received through such pad.

  One cannot link two pads with the same direction.
  """
  @type direction_t :: :source | :sink

  @availabilities [:always, :on_request]

  @typedoc """
  Defines possible pad availabilities:
  - `:always` - a static pad, which can remain unlinked in `stopped` state only.
  - `:on_request` - a dynamic pad, instance of which is created every time it is
  linked to another pad. Thus linking the pad with _k_ other pads, creates _k_
  instances of the pad, and links each with another pad.
  For information on static/dynamic pad modes, see `t:availability_mode_t/0`.
  """
  def_type_from_list availability_t :: @availabilities

  defguard is_availability(term) when term in @availabilities

  @typedoc """
  Type describing pad availability modes:
  - `:static` - there always exist exactly one instance of such pad.
  - `:dynamic` - multiple instances of such pad may be created and removed (which
  entails executing `handle_pad_added` and `handle_pad_removed` callbacks,
  respectively).
  """
  @type availability_mode_t :: :static | :dynamic

  @doc """
  Determines whether pad availability requires exactly one instance of a pad
  (static) or allows multiple ones (dynamic).
  """
  @spec availability_mode(availability_t) :: availability_mode_t
  def availability_mode(:always), do: :static

  def availability_mode(:on_request), do: :dynamic

  @typedoc """
  Type describing possible pad modes. They are strictly related to pad directions:
  - `:push` source pad - element can send data through such pad whenever it wants.
  - `:push` sink pad - element has to deal with data whenever it comes through
  such pad, and do it fast enough not to let data accumulate on such pad, what
  may lead to overflow of element process erlang queue, which is highly unwanted.
  - `:pull` source pad - element can send data through such pad only if it have
  already received demand on the pad. Sending small, limited amount of
  undemanded data is supported and handled by `Membrane.PullBuffer`.
  - `:pull` sink pad - element receives through such pad only data that it has
  previously demanded, so that no undemanded data can arrive.

  Linking pads with different modes is possible, but only in case of source pad
  working in push mode, and sink in pull mode. Moreover, toilet mode of
  `Membrane.PullBuffer` has to be enabled then.

  For more information on transfering data and demands, see docs for element
  callbacks in `Membrane.Element.Base.*`.
  """
  @type mode_t :: :push | :pull

  @typedoc """
  Type defining possible caps that can be set on the pad. To link two pads,
  they need to have some common caps.
  """
  @type caps_t :: Membrane.Element.Caps.Matcher.caps_spec_t()
end
