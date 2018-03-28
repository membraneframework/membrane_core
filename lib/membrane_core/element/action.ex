defmodule Membrane.Element.Action do
  @type demand_filter_payload_t ::
          {Pad.name_t(), {:source, Pad.name_t()} | :self, size :: non_neg_integer}
  @type demand_sink_payload_t :: {Pad.name_t(), {:set_to, size :: non_neg_integer}}
  @type demand_common_payload_t :: Pad.name_t() | {Pad.name_t(), size :: non_neg_integer}

  @type event_t :: {:event, {Pad.name_t(), Event.t()}}
  @type message_t :: {:message, Message.t()}
  @type split_t :: {:split, {callback_name :: atom, args_list :: [[any]]}}
  @type caps_t :: {:caps, {Pad.name_t(), Caps.t()}}
  @type buffer_t :: {:buffer, {Pad.name_t(), Buffer.t() | [Buffer.t()]}}
  @type demand_t ::
          {:demand, demand_common_payload_t | demand_filter_payload_t | demand_sink_payload_t}
  @type redemand_t :: {:redemand, Pad.name_t()}
  @type forward_t :: {:forward, Buffer.t() | Caps.t() | Event.t()}
  @type playback_change_t :: {:playback_change, :suspend | :resume}

  @typedoc """
  Type that defines a single action that may be returned from handle_*
  callbacks. Depending on callback and playback state there may be different
  actions available.
  """
  @type t ::
          event_t
          | message_t
          | split_t
          | caps_t
          | buffer_t
          | demand_t
          | redemand_t
          | forward_t
          | playback_change_t
end
