defmodule Jido.Chat.Signal.AdapterTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.Signal.Adapter

  defmodule FakeTransport do
    @behaviour Jido.Chat.Signal.Transport

    def send_message("+15555550100", "hello", _opts), do: {:ok, %{"timestamp" => 1_776_000_000}}
    def list_groups(_opts), do: {:ok, []}
  end

  test "sends a message through signal-cli transport" do
    assert {:ok, response} =
             Adapter.send_message("+15555550100", "hello", transport: FakeTransport)

    assert response.external_message_id == "1776000000"
  end

  test "normalizes signal-cli receive notification" do
    payload = %{
      "envelope" => %{
        "sourceNumber" => "+15555550100",
        "sourceName" => "Tester",
        "timestamp" => 1_776_000_000,
        "dataMessage" => %{"timestamp" => 1_776_000_000, "message" => "hello"}
      }
    }

    assert {:ok, incoming} = Adapter.transform_incoming(payload)
    assert incoming.external_room_id == "+15555550100"
    assert incoming.text == "hello"
  end
end
