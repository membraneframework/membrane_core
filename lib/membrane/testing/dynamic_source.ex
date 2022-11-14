defmodule Membrane.Testing.DynamicSource do
  @moduledoc """
  Testing Element for supplying data based on generator function or payloads passed
  through options. It is very similar to `Membrane.Testing.Source` but is has dynamic
  pad instead of static.

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
  generator_function = fn state, pad, size ->
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
          (state :: any(), pad :: Pad.ref_t(), buffers_cnt :: pos_integer ->
             {[Action.t()], state :: any()})

  def_output_pad :output, accepted_format: _any, availability: :on_request

  def_options output: [
                spec: {initial_state :: any(), generator()} | Enum.t(),
                default: {0, &__MODULE__.default_buf_gen/3},
                description: """
                If `output` is an enumerable with `t:Membrane.Payload.t/0` then
                buffer containing those payloads will be sent through the
                `:output` pad and followed by `t:Membrane.Element.Action.end_of_stream_t/0`.

                If `output` is a `{initial_state, function}` tuple then the
                the function will be invoked each time `handle_demand` is called.
                It is an action generator that takes two arguments.
                The first argument is the state that is initially set to
                `initial_state`. The second one defines the pad on which the demand
                has been requested. The third one defines the size of the demand.
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
                Stream format to be sent before the `output`.
                """
              ]

  @spec default_buf_gen(integer(), Pad.ref_t(), integer()) :: {[Action.t()], integer()}
  def default_buf_gen(generator_state, pad, size) do
    buffers =
      generator_state..(size + generator_state - 1)
      |> Enum.map(fn generator_state ->
        %Buffer{payload: <<generator_state::16>>}
      end)

    action = [buffer: {pad, buffers}]
    {action, generator_state + size}
  end

  @impl true
  def handle_init(_ctx, opts) do
    opts = Map.from_struct(opts)

    case opts.output do
      {initial_state, generator} when is_function(generator) ->
        {[],
         Map.merge(opts, %{
           type: :generator,
           generator: generator,
           generator_state: initial_state,
           state_for_pad: %{}
         })}

      _enumerable_output ->
        {[], Map.merge(opts, %{type: :enum, output: opts.output, output_for_pad: %{}})}
    end
  end

  @impl true
  def handle_playing(ctx, state) do
    actions = Map.keys(ctx.pads) |> Enum.map(&{:stream_format, {&1, state.stream_format}})
    {actions, state}
  end

  @impl true
  def handle_pad_added(pad, _ctx, %{type: :enum} = state) do
    {[], Map.update!(state, :output_for_pad, &Map.put(&1, pad, state.output))}
  end

  @impl true
  def handle_pad_added(pad, _ctx, %{type: :generator} = state) do
    {[], Map.update!(state, :state_for_pad, &Map.put(&1, pad, state.generator_state))}
  end

  @impl true
  def handle_demand(pad, _size, :buffers, _ctx, %{type: :enum} = state) do
    output_for_pad = state.output_for_pad[pad]

    if length(output_for_pad) > 0 do
      [payload | rest] = output_for_pad

      {
        [
          {:buffer, {pad, %Buffer{payload: payload}}},
          {:redemand, pad}
        ],
        Map.update!(state, :output_for_pad, &Map.put(&1, pad, rest))
      }
    else
      {[end_of_stream: pad], state}
    end
  end

  @impl true
  def handle_demand(pad, _size, :buffers, _ctx, %{type: :generator} = state) do
    state_for_pad = state.state_for_pad[pad]
    {actions, new_state} = state.generator.(state_for_pad, pad, 1)

    {actions ++ [redemand: pad], Map.update!(state, :state_for_pad, &Map.put(&1, pad, new_state))}
  end
end
