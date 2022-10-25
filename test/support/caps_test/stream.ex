defmodule Membrane.Support.CapsTest.Stream do
  @moduledoc """
  Stream definition used in caps test.
  """

  @type t() :: %__MODULE__{
          format:
            nil | FormatAcceptedByAll | FormatAcceptedByOuterBins | FormatAcceptedByInnerBins
        }

  defstruct [:format]

  defmodule FormatAcceptedByAll do
    @moduledoc """
    Stream format definition used in caps tests.
    Accepted by caps patterns in all bins used in caps tests.
    """
  end

  defmodule FormatAcceptedByOuterBins do
    @moduledoc """
    Stream format definition used in caps test.
    Accepted by caps patterns in outer bins used in caps tests.
    """
  end

  defmodule FormatAcceptedByInnerBins do
    @moduledoc """
    Stream format definition used in caps test.
    Accepted by caps patterns in inner bins used in caps tests.
    """
  end
end
