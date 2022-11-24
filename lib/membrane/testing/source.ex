defmodule Membrane.Testing.Source do
  @moduledoc """
  Testing Element for supplying data based on generator function or payloads passed
  through options.

  ## Example usage

  As mentioned earlier you can use this element in one of two ways, providing
  either a generator function or an `Enumerable.t`.

  If you provide an `Enumerable.t` with payloads, then each of those payloads will
  be wrapped in a `Membrane.Buffer` and sent through `:output` pad.
  ```
  %Source{output: [0xA1, 0xB2, 0xC3, 0xD4]}
  ```

  In order to specify `Membrane.Testing.Source` with generator function you need
  to provide initial state and function that matches `t:generator/0` type. This
  function should take state and demand size as its arguments and return
  a tuple consisting of actions that element will return during the
  `c:Membrane.Element.WithOutputPads.handle_demand/5`
  callback and new state.
  ```
  generator_function = fn state, size ->
    #generate some buffers
    {actions, state + 1}
  end
  %Source{output: {1, generator_function}}
  ```
  """

  use Membrane.Source

  alias Membrane.Buffer
  alias Membrane.Element.Action

  @type generator ::
          (state :: any(), buffers_cnt :: pos_integer -> {[Action.t()], state :: any()})

  def_output_pad :output, accepted_format: _any

  def_options output: [
                spec: {initial_state :: any(), generator} | Enum.t(),
                default: {0, &__MODULE__.default_buf_gen/2},
                description: """
                If `output` is an enumerable with `t:Membrane.Payload.t/0` then
                buffer containing those payloads will be sent through the
                `:output` pad and followed by `t:Membrane.Element.Action.end_of_stream_t/0`.

                If `output` is a `{initial_state, function}` tuple then the
                the function will be invoked each time `handle_demand` is called.
                It is an action generator that takes two arguments.
                The first argument is the state that is initially set to
                `initial_state`. The second one defines the size of the demand.
                Such function should return `{actions, next_state}` where
                `actions` is a list of actions that will be returned from
                `handle_demand/4` and `next_state` is the value that will be
                used for the next call.
                """
              ],
              stream_format: [
                spec: struct(),
                default: %Membrane.RemoteStream{},
                description: """
                StreamFormat to be sent before the `output`.
                """
              ]

  @impl true
  def handle_init(_ctx, opts) do
    opts = Map.from_struct(opts)

    case opts.output do
      {initial_state, generator} when is_function(generator) ->
        {[], opts |> Map.merge(%{generator_state: initial_state, output: generator})}

      _enumerable_output ->
        {[], opts}
    end
  end

  @impl true
  def handle_playing(_ctx, state) do
    {[stream_format: {:output, state.stream_format}], state}
  end

  @impl true
  def handle_demand(:output, size, :buffers, _ctx, state) do
    get_actions(state, size)
  end

  @spec default_buf_gen(integer(), integer()) :: {[Action.t()], integer()}
  def default_buf_gen(generator_state, size) do
    buffers =
      generator_state..(size + generator_state - 1)
      |> Enum.map(fn generator_state ->
        %Buffer{payload: <<generator_state::16>>}
      end)

    action = [buffer: {:output, buffers}]
    {action, generator_state + size}
  end

  @doc """
  Creates output with generator function from list of buffers.
  """
  @spec output_from_buffers([Buffer.t()]) :: {[Buffer.t()], generator()}
  def output_from_buffers(data) do
    fun = fn state, size ->
      {buffers, leftover} = Enum.split(state, size)
      buffer_action = [{:buffer, {:output, buffers}}]
      event_action = if leftover == [], do: [end_of_stream: :output], else: []
      to_send = buffer_action ++ event_action
      {to_send, leftover}
    end

    {data, fun}
  end

  defp get_actions(%{generator_state: generator_state, output: actions_generator} = state, size)
       when is_function(actions_generator) do
    {actions, generator_state} = actions_generator.(generator_state, size)
    {actions, %{state | generator_state: generator_state}}
  end

  defp get_actions(%{output: output} = state, size) do
    {payloads, output} = Enum.split(output, size)
    buffers = Enum.map(payloads, &%Buffer{payload: &1})

    actions =
      case output do
        [] -> [buffer: {:output, buffers}, end_of_stream: :output]
        _non_empty -> [buffer: {:output, buffers}]
      end

    {actions, %{state | output: output}}
  end
end
