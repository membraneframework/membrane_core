defmodule Membrane.Testing.Source do
  @moduledoc """
  Testing Element for supplying data based on generator function passed through options.
  """

  use Membrane.Element.Base.Source
  use Bunch
  alias Membrane.Buffer
  alias Membrane.Element.Action

  def_output_pads output: [caps: :any]

  def_options actions_generator: [
                type: :function,
                spec: (non_neg_integer, non_neg_integer -> [Action.t()]),
                default: &__MODULE__.default_buf_gen/2,
                description: """
                Function invoked each time `handle_demand` is invoked.
                It is an action generator that takes two arguments.
                First argument is counter which is incremented by 1 every call
                and second argument represents size of demand.
                """
              ]

  @impl true
  def handle_init(opts) do
    {:ok, opts |> Map.merge(%{cnt: 0})}
  end

  @impl true
  def handle_demand(:output, size, :buffers, _ctx, %{cnt: cnt} = state) do
    {actions, cnt} = state.actions_generator.(cnt, size)

    {{:ok, actions}, %{state | cnt: cnt}}
  end

  def default_buf_gen(cnt, size) do
    cnt..(size + cnt - 1)
    |> Enum.map(fn cnt ->
      buf = %Buffer{payload: <<cnt::16>>}

      {:buffer, {:output, buf}}
    end)
    ~> {&1, cnt + size}
  end
end
