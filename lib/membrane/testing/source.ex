defmodule Membrane.Testing.Source do
  @moduledoc """
  Testing Element for supplying data based on generator function passed through options.
  """

  use Membrane.Element.Base.Source
  use Bunch
  alias Membrane.Buffer
  alias Membrane.Element.Action
  alias Membrane.Event.EndOfStream
  require Bunch.Code

  def_output_pad :output, caps: :any

  def_options output: [
                spec: (non_neg_integer, non_neg_integer -> {[Action.t()], integer()}) | Enum.t(),
                default: &__MODULE__.default_buf_gen/2,
                description: """
                If `output` is an enumerable with `Membrane.Payload.t()` then
                buffer containing those payloads will be sent through the
                `:output` pad and followed by `Membrane.Event.EndOfStream`.

                If `output` is a function then it will be invoked each time
                `handle_demand` is invoked. It is an action generator that takes
                two arguments. The first argument is counter which is incremented by
                1 every call and second argument represents the size of demand.
                """
              ]

  @impl true
  def handle_init(%__MODULE__{output: output} = opts) do
    opts = Map.from_struct(opts)

    if is_function(output) do
      {:ok, opts |> Map.merge(%{cnt: 0})}
    else
      {:ok, opts}
    end
  end

  @impl true
  def handle_demand(:output, size, :buffers, _ctx, state) do
    {actions, state} = get_actions(state, size)
    {{:ok, actions}, state}
  end

  @spec default_buf_gen(integer(), integer()) :: {[Action.t()], integer()}
  def default_buf_gen(cnt, size) do
    cnt..(size + cnt - 1)
    |> Enum.map(fn cnt ->
      buf = %Buffer{payload: <<cnt::16>>}

      {:buffer, {:output, buf}}
    end)
    ~> {&1, cnt + size}
  end

  defp get_actions(%{cnt: cnt, output: actions_generator} = state, size)
       when is_function(actions_generator) do
    {actions, cnt} = actions_generator.(cnt, size)
    {actions, %{state | cnt: cnt}}
  end

  defp get_actions(%{output: output} = state, size) do
    {payloads, output} = Enum.split(output, size)
    buffers = Enum.map(payloads, &%Buffer{payload: &1})

    actions =
      case output do
        [] -> [buffer: {:output, buffers}, event: {:output, %EndOfStream{}}]
        _ -> [buffer: {:output, buffers}]
      end

    {actions, %{state | output: output}}
  end
end
