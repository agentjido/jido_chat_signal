defmodule Jido.Chat.Signal.Transport do
  @moduledoc "Transport contract for signal-cli-backed calls."

  @callback send_message(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback list_groups(keyword()) :: {:ok, list(map())} | {:error, term()}
  @callback receive_messages(keyword()) :: {:ok, [map()]} | {:error, term()}

  @optional_callbacks receive_messages: 1
end
