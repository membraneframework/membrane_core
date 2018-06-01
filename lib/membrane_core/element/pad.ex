defmodule Membrane.Element.Pad do
  @moduledoc """
  Typespecs and utils for element pads.
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

  @availabilities [:always, :on_request]

  @typedoc """
  Defines possible pad availabilities.
  """
  def_type_from_list availability_t :: @availabilities

  defguard is_availability(term) when term in @availabilities

  @doc """
  Determines whether pad availability requires exactly one instance of a pad
  (static) or allows multiple ones (dynamic).
  """
  @spec availability_mode(availability_t) :: :static | :dynamic
  def availability_mode(:always), do: :static

  def availability_mode(:on_request), do: :dynamic
end
