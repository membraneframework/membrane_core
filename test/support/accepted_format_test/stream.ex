defmodule Membrane.Support.AcceptedFormatTest.StreamFormat do
  @moduledoc """
  Stream formats definitions used in stream format test.
  """

  @type t() :: %__MODULE__{
          format:
            nil | FormatAcceptedByAll | FormatAcceptedByOuterBins | FormatAcceptedByInnerBins
        }

  defstruct [:format]

  defmodule AcceptedByAll do
    @moduledoc """
    Stream format definition used in stream format tests.
    Accepted by all bins used in stream format tests.
    """
  end

  defmodule AcceptedByOuterBins do
    @moduledoc """
    Stream format definition used in stream format test.
    Accepted by outer bins used in stream format tests.
    """
  end

  defmodule AcceptedByInnerBins do
    @moduledoc """
    Stream format definition used in stream format test.
    Accepted by inner bins used in stream format tests.
    """
  end
end
