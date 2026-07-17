defmodule Virtuoso.Channel do
  @moduledoc """
  The behaviour every channel adapter implements.

  A channel maps a transport's wire format to and from the framework's
  channel-neutral `Virtuoso.Impression`. The rest of the framework only ever
  sees impressions; adapters own the translation.

  This behaviour is the *pure* part of a channel — translation and webhook
  verification. The concrete transport (a Phoenix Channels socket, an HTTP
  webhook endpoint) lives in the host application, so the framework library
  stays free of Phoenix. Web chat is the first-class channel; the behaviour is
  the extension point for others.

  ## Callbacks

    * `translate_in/1` — turn a raw inbound payload into an `%Impression{}`,
      or `{:error, reason}` if the payload is malformed.
    * `send_out/2` — shape an outbound reply (an impression's context + reply
      text) into the transport's wire format.
    * `verify_webhook/2` — verify an inbound webhook is authentic. Channels whose
      transport is a public endpoint delegate to `Virtuoso.Channel.Signature`;
      session-authenticated channels (web chat) return `:ok`.
  """

  alias Virtuoso.Impression

  @type raw :: map()
  @type reply_text :: String.t()

  @doc "Translate a raw inbound payload into an impression."
  @callback translate_in(raw()) :: {:ok, Impression.t()} | {:error, term()}

  @doc "Shape an outbound reply into the transport's wire format."
  @callback send_out(Impression.t(), reply_text()) :: {:ok, term()} | {:error, term()}

  @doc "Verify an inbound webhook payload's authenticity."
  @callback verify_webhook(raw_body :: binary(), opts :: keyword()) ::
              :ok | {:error, term()}
end
