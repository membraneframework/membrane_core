defmodule Membrane.Integration.TestingSource do
  use Membrane.Element.Base.Source
  alias Membrane.Buffer
  use Bunch

  def_output_pads out: [caps: :any]

  def_options actions_generator: [
                type: :function,
                spec: (non_neg_integer, non_neg_integer -> [Membrane.Action.t()]),
                default: &__MODULE__.default_buf_gen/2
              ]

  @impl true
  def handle_init(opts) do
    {:ok, opts |> Map.merge(%{cnt: 0})}
  end

  @impl true
  def handle_demand(
        :out,
        size,
        :buffers,
        _ctx,
        %{cnt: cnt} = state
      ) do
    {actions, cnt} = state.actions_generator.(cnt, size)

    {{:ok, actions}, %{state | cnt: cnt}}
  end

  def default_buf_gen(cnt, size) do
    cnt..(size + cnt - 1)
    |> Enum.map(fn cnt ->
      buf = %Buffer{payload: <<cnt::16>>}

      {:buffer, {:out, buf}}
    end)
    ~> {&1, cnt + size}
  end
end
