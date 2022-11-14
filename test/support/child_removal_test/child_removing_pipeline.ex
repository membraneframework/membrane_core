defmodule Membrane.Support.ChildRemovalTest.ChildRemovingPipeline do
  @moduledoc false
  use Membrane.Pipeline

  import Membrane.ChildrenSpec

  alias Membrane.Support.ChildRemovalTest.FilterToBeRemoved
  alias Membrane.Support.ChildRemovalTest.SourceNotyfingWhenPadRemoved

  @impl true
  def handle_init(_ctx, _opts) do
    structure1 = [child(:source, SourceNotyfingWhenPadRemoved)]
    spec1 = structure1

    structure2 = [
      get_child(:source) |> via_out(:first) |> child(:filter1, FilterToBeRemoved),
      get_child(:source) |> via_out(:second) |> child(:filter2, FilterToBeRemoved)
    ]

    spec2 = {structure2, children_group_id: :first_crash_group, crash_group_mode: :temporary}

    structure3 = [get_child(:source) |> via_out(:third) |> child(:filter3, FilterToBeRemoved)]
    spec3 = {structure3, children_group_id: :first_crash_group, crash_group_mode: :temporary}

    structure4 = [
      get_child(:source) |> via_out(:fourth) |> child(:filter4, FilterToBeRemoved),
      get_child(:source) |> via_out(:fifth) |> child(:filter5, FilterToBeRemoved)
    ]

    spec4 = {structure4, children_group_id: :second_crash_group, crash_group_mode: :temporary}

    {[spec: spec1, spec: spec2, spec: spec3, spec: spec4], %{}}
  end
end
