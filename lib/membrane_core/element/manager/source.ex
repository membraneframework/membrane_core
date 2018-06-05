defmodule Membrane.Element.Manager.Source do
  @moduledoc """
  Module responsible for managing source elements - executing callbacks and
  handling actions.
  """

  use Membrane.Element.Manager.Log
  alias Membrane.Element.Manager.{ActionExec, Common, State}
  import Membrane.Element.Pad, only: [is_pad_name: 1]
  alias Membrane.Element.Context
  use Membrane.Element.Manager.Common

  # Private API

  def handle_action({:buffer, {pad_name, buffer}}, cb, _params, state)
      when is_pad_name(pad_name) do
    ActionExec.send_buffer(pad_name, buffer, cb, state)
  end

  def handle_action({:caps, {pad_name, caps}}, _cb, _params, state)
      when is_pad_name(pad_name) do
    ActionExec.send_caps(pad_name, caps, state)
  end

  def handle_action({:redemand, src_name}, cb, _params, state)
      when is_pad_name(src_name) and cb != :handle_demand do
    ActionExec.handle_redemand(src_name, state)
  end

  defdelegate handle_action(action, callback, params, state),
    to: Common,
    as: :handle_invalid_action

  def handle_redemand(src_name, state) do
    handle_demand(src_name, 0, state)
  end

  defdelegate handle_demand(pad_name, size, state), to: Common
end
