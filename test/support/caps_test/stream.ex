defmodule Membrane.Support.CapsTest.Stream do
  @moduledoc """
  Stream definition used in caps test.
  """

  @type t() :: %__MODULE__{
          format: nil | FormatA | FormatB
        }

  defstruct [:format]

  defmodule FormatA do
    @moduledoc """
    Stream format definition used in caps test.
    """
  end

  defmodule FormatB do
    @moduledoc """
    Stream format definition used in caps test.
    """
  end
end
