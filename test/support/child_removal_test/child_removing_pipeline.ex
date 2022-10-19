defmodule Membrane.Support.ChildRemovalTest.ChildRemovingPipeline do
  @moduledoc false
  use Membrane.Pipeline

  import Membrane.ChildrenSpec

  alias Membrane.ChildrenSpec
  alias Membrane.Support.ChildRemovalTest.FilterToBeRemoved
  alias Membrane.Support.ChildRemovalTest.SourceNotyfingWhenPadRemoved

  @impl true
  def handle_init(_opts) do
    structure1 = [child(:source, SourceNotyfingWhenPadRemoved)]
    spec1 = %ChildrenSpec{structure: structure1}

    structure2 = [
      get_child(:source) |> via_out(:first) |> child(:filter1, FilterToBeRemoved),
      get_child(:source) |> via_out(:second) |> child(:filter2, FilterToBeRemoved)
    ]

    spec2 = %ChildrenSpec{structure: structure2, children_group_id: :first_crash_group}

    structure3 = [get_child(:source) |> via_out(:third) |> child(:filter3, FilterToBeRemoved)]
    spec3 = %ChildrenSpec{structure: structure3, children_group_id: :first_crash_group}

    structure4 = [
      get_child(:source) |> via_out(:fourth) |> child(:filter4, FilterToBeRemoved),
      get_child(:source) |> via_out(:fifth) |> child(:filter5, FilterToBeRemoved)
    ]

    spec4 = %ChildrenSpec{structure: structure4, children_group_id: :second_crash_group}

    {{:ok, spec: spec1, spec: spec2, spec: spec3, spec: spec4}, %{}}
  end
end
