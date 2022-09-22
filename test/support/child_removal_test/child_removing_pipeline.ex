defmodule Membrane.Support.ChildRemovalTest.ChildRemovingPipeline do
  @moduledoc false
  use Membrane.Pipeline

  import ParentSpec

  alias Membrane.Support.ChildRemovalTest.FilterToBeRemoved
  alias Membrane.Support.ChildRemovalTest.SourceNotyfingWhenPadRemoved

  @impl true
  def handle_init(_opts) do
    structure1 = [spawn_child(:source, SourceNotyfingWhenPadRemoved)]
    spec1 = %ParentSpec{structure: structure1}

    structure2 = [
      link(:source) |> via_out(:first) |> to(:filter1, FilterToBeRemoved),
      link(:source) |> via_out(:second) |> to(:filter2, FilterToBeRemoved)
    ]

    spec2 = %ParentSpec{structure: structure2, children_group_id: :first_crash_group}

    structure3 = [link(:source) |> via_out(:third) |> to(:filter3, FilterToBeRemoved)]
    spec3 = %ParentSpec{structure: structure3, children_group_id: :first_crash_group}

    structure4 = [
      link(:source) |> via_out(:fourth) |> to(:filter4, FilterToBeRemoved),
      link(:source) |> via_out(:fifth) |> to(:filter5, FilterToBeRemoved)
    ]

    spec4 = %ParentSpec{structure: structure4, children_group_id: :second_crash_group}

    {{:ok, spec: spec1, spec: spec2, spec: spec3, spec: spec4}, %{}}
  end
end
