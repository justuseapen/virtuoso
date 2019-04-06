defmodule Virtuoso.FacebookGraphApi do

  # Facebook Graph API interface behaviour

  @callback send_messenger_response(response :: map()) :: :ok | :error
  @callback send_messenger_response(response :: map(), token :: String.t()) :: :ok | :error

end
