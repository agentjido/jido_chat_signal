defmodule Jido.Chat.Signal.Transport do
  @moduledoc "Transport contract for signal-cli JSON-RPC calls."

  @callback send_message(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback list_groups(keyword()) :: {:ok, list(map())} | {:error, term()}
end
