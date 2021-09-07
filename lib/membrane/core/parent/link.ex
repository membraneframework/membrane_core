defmodule Membrane.Core.Parent.Link do
  @moduledoc false

  use Bunch.Access

  alias __MODULE__.Endpoint

  @enforce_keys [:from, :to]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          from: Endpoint.t(),
          to: Endpoint.t()
        }
end
