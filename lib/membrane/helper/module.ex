defmodule Membrane.Helper.Module do
  @moduledoc """
  A set of functions for easier manipulation on modules
  """

  def check_behaviour(module, fun) do
    module |> loaded_and_function_exported?(fun, 0) and module |> apply(fun, [])
  end

  def struct(module) do
    if module |> loaded_and_function_exported?(:__struct__, 0),
      do: module.__struct__([]),
      else: nil
  end

  def loaded_and_function_exported?(module, function, arity) do
    module |> Code.ensure_loaded?() and module |> function_exported?(function, arity)
  end
end
