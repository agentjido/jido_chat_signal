defmodule Jido.Chat.Signal do
  @moduledoc "Signal adapter package for `Jido.Chat` using `signal-cli`."

  alias Jido.Chat.Signal.Adapter

  @doc "Returns the canonical Signal adapter module."
  def adapter, do: Adapter

  @doc "Returns the incoming facts normalized by Signal."
  def event_definitions do
    [Jido.Chat.Signal.MessageReceived, Jido.Chat.Signal.NormalizationFailed]
  end
end
