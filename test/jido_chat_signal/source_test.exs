defmodule Jido.Chat.Signal.SourceTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.Client
  alias Jido.Chat.Signal.{Adapter, Source}

  defmodule Receiver do
    def receive_messages(opts) do
      send(opts[:test_pid], :received)

      {:ok,
       [
         %{
           "envelope" => %{
             "sourceNumber" => "+15555550100",
             "timestamp" => 1,
             "dataMessage" => %{"timestamp" => 1, "message" => "hello"}
           }
         }
       ]}
    end
  end

  test "reads receive batches through the shared Sensor source contract" do
    client = Client.new!(Adapter, id: "signal-source")

    assert {:ok, [signal], cursor} =
             Source.read(client, nil, receiver: Receiver, test_pid: self())

    assert_received :received
    assert signal.type == "jido.chat.message.received"
    assert is_binary(cursor)
    assert Source.mode() == :poll
    assert Source.poll_interval(poll_interval_ms: 50) == 50
  end
end
