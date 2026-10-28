defmodule Jido.Chat.Signal.Source do
  @moduledoc "Receive-only Signal polling source for the shared Chat Sensor."
  @behaviour Jido.Chat.Sensor.Source

  alias Jido.Chat.Client
  alias Jido.Chat.Signal

  @impl true
  def mode, do: :poll

  @impl true
  def signal_types, do: Enum.map(Signal.event_definitions(), & &1.type())

  @impl true
  def poll_interval(opts), do: positive_integer(opts[:poll_interval_ms], 1_000)

  @impl true
  def key(client, _opts) do
    options = Client.options(client)
    identity = {options[:account], options[:endpoint], options[:executable]}
    :crypto.hash(:sha256, :erlang.term_to_binary(identity, [:deterministic]))
  end

  @impl true
  def read(client, cursor, opts) do
    receiver = Keyword.get(opts, :receiver, client.transport)

    private =
      Client.options(client) |> Keyword.merge(Keyword.drop(opts, [:receiver, :poll_interval_ms]))

    with true <- function_exported?(receiver, :receive_messages, 1),
         {:ok, messages} when is_list(messages) <- receiver.receive_messages(private),
         {:ok, delivery} <- Jido.Chat.normalize(client, messages) do
      next_cursor = if messages == [], do: cursor, else: delivery.id
      {:ok, delivery.signals, next_cursor}
    else
      false -> {:error, :receive_not_supported}
      {:ok, _} -> {:error, :invalid_receive_result}
      {:error, _} = error -> error
      _ -> {:error, :invalid_receive_result}
    end
  end

  defp positive_integer(value, _) when is_integer(value) and value > 0, do: value
  defp positive_integer(_, default), do: default
end
