defmodule Membrane.Bin do
  @callback membrane_bin?() :: true
  # TODO
  @callback handle_init(opts :: any) :: {{:ok, __MODULE__.Spec.t()}, state :: any}

  alias Membrane.Core.Message
  alias Membrane.Element
  alias Membrane.Core.Element.PadsSpecs

  require Message

  defmodule Spec do
    defstruct children: [],
              links: %{}
  end

  def start_link(name, module, options, process_options) do
    # TODO inject first argument later? (self)
    # {:ok, pid} = Element.start_link(self(), module, name, options),
    Membrane.Bin.Pipeline.start_link(name, module, options, process_options)
  end

  def bin?(module) do
    module |> Bunch.Module.check_behaviour(:membrane_bin?)
  end

  defmacro this_bin_marker do
    quote do
      {unquote(__MODULE__), :this_bin}
    end
  end

  # TODO establish options for the private pads
  defmacro def_input_pad(name, spec) do
    input = PadsSpecs.def_pad(name, :input, spec)
    output = PadsSpecs.def_pad({:private, name}, :output, caps: :any)

    quote do
      unquote(input)
      unquote(output)
    end
  end

  defmacro def_output_pad(name, spec) do
    output = PadsSpecs.def_pad(name, :output, spec)
    input = PadsSpecs.def_pad({:private, name}, :input, caps: :any, demand_unit: :buffers)

    quote do
      unquote(output)
      unquote(input)
    end
  end

  defmacro __using__(_) do
    quote do
      @behaviour unquote(__MODULE__)

      import Membrane.Element.Base, only: [def_options: 1]
      import unquote(__MODULE__), only: [def_input_pad: 2, def_output_pad: 2]

      @impl true
      def membrane_bin?, do: true

      # TODO think of something better to represent this bin
      defp this_bin, do: unquote(__MODULE__).this_bin_marker()

      def membrane_element?, do: true

      # For now we only support filter bins
      def membrane_element_type, do: :filter
    end
  end
end
