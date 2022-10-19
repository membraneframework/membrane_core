defmodule Membrane.Core.Parent.Link do
  @moduledoc false

  use Bunch.Access

  alias __MODULE__.Endpoint

  @enforce_keys [:id, :from, :to]
  defstruct @enforce_keys ++ [linked?: false, spec_ref: nil]

  @type id :: reference()

  @type t :: %__MODULE__{
          id: id(),
          from: Endpoint.t(),
          to: Endpoint.t(),
          linked?: boolean(),
          spec_ref: Membrane.Core.Parent.ChildLifeController.spec_ref_t()
        }
end
