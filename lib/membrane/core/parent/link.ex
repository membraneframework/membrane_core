defmodule Membrane.Core.Parent.Link do
  @moduledoc false

  use Bunch.Access

  alias __MODULE__.Endpoint

  @enforce_keys [:id, :from, :to]
  defstruct @enforce_keys ++ [linked?: false, spec_ref: nil]

  @type t :: %__MODULE__{
          id: Bunch.ShortRef.t(),
          from: Endpoint.t(),
          to: Endpoint.t()
        }
end
