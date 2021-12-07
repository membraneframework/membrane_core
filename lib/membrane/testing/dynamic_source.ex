defmodule Membrane.Testing.DynamicSource do
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

  def_output_pad :output, availability: :on_request, caps: :any

  def_options output: [
                spec: {initial_state :: any(), generator} | Enum.t(),
                description: """
                If `output` is an enumerable with `Membrane.Payload.t()` then
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
              caps: [
                spec: struct(),
                default: %Membrane.RemoteStream{},
                description: """
                Caps to be sent before the `output`.
                """
              ]

  @impl true
  def handle_init(opts) do
    opts = Map.from_struct(opts)

    case opts.output do
      {initial_state, generator} when is_function(generator) ->
        {:ok, opts |> Map.merge(%{generator_state: initial_state, output: generator, pad: nil})}

      _enumerable_output ->
        {:ok, opts |> Map.merge(%{pad: nil})}
    end
  end

  @impl true
  def handle_pad_added(pad, _ctx, state) do
    {:ok, %{state | pad: pad}}
  end

  @impl true
  def handle_prepared_to_playing(_ctx, state) do
    {{:ok, caps: {state.pad, state.caps}}, state}
  end

  @impl true
  def handle_demand(_pad, size, :buffers, _ctx, state) do
    {actions, state} = get_actions(state, size)
    {{:ok, actions}, state}
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
        [] -> [buffer: {state.pad, buffers}, end_of_stream: state.pad]
        _non_empty -> [buffer: {state.pad, buffers}]
      end

    {actions, %{state | output: output}}
  end
end
