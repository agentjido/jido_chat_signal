defmodule Jido.Chat.Signal.AdapterTest do
  use Jido.Chat.AdapterTestKit, adapter: Jido.Chat.Signal.Adapter

  alias Jido.Chat.Client
  alias Jido.Chat.Signal.Adapter

  defmodule FakeTransport do
    @behaviour Jido.Chat.Signal.Transport

    @impl true
    def send_message(target, text, opts) do
      if pid = opts[:test_pid], do: send(pid, {:signal_send, target, text, opts})
      {:ok, %{"timestamp" => 1_776_000_000}}
    end

    @impl true
    def list_groups(_opts), do: {:ok, []}

    @impl true
    def receive_messages(_opts), do: {:ok, []}
  end

  setup do
    client =
      Client.new!(Adapter,
        id: "signal-test",
        transport: FakeTransport,
        credentials: %{test_pid: self()}
      )

    %{client: client}
  end

  test "sends text and inline files through public Chat Actions", %{client: client} do
    assert {:ok, sent} = Jido.Chat.send_text(client, "+15555550100", "hello")
    assert sent.data["result"]["id"] == "1776000000"
    assert_received {:signal_send, "+15555550100", "hello", _opts}

    source = %{"content_base64" => Base.encode64("report"), "filename" => "report.txt"}

    assert {:ok, file} =
             Jido.Chat.send_file(client, "+15555550100", source, caption: "file caption")

    assert file.data["result"]["id"] == "1776000000"
    assert_received {:signal_send, "+15555550100", "file caption", opts}
    assert [%{data: encoded, filename: "report.txt"}] = opts[:attachments]
    assert encoded == Base.encode64("report")
  end

  test "normalizes messages, quotes, groups, and attachment references", %{client: client} do
    payload =
      message(1_776_000_000, "hello")
      |> put_in(["envelope", "dataMessage", "groupInfo"], %{"groupId" => "group/1"})
      |> put_in(["envelope", "dataMessage", "quote"], %{"id" => 1_775_999_999})
      |> put_in(["envelope", "dataMessage", "attachments"], [
        %{"contentType" => "image/png", "filename" => "image.png", "size" => 123}
      ])

    assert {:ok, first} = Jido.Chat.normalize(client, payload)
    assert {:ok, second} = Jido.Chat.normalize(client, payload)
    assert first.id == second.id
    assert [signal] = first.signals
    assert signal.type == "jido.chat.message.received"
    assert signal.data["room_id"] == "group:group/1"
    assert signal.data["thread_id"] == "group/1"
    assert signal.data["reply_to_id"] == "1775999999"
    assert [%{"kind" => "image", "resource_ref" => reference}] = signal.data["media"]
    assert reference["client_id"] == client.id
    refute Jason.encode!(Jido.Signal.to_map(signal)) =~ "\"size\""
  end

  test "keeps stable ordered facts and reports invalid provider items", %{client: client} do
    input = [message(1, "first"), nil, message(2, "last")]
    assert {:ok, first} = Jido.Chat.normalize(client, input)
    assert {:ok, second} = Jido.Chat.normalize(client, input)
    assert first.id == second.id

    assert Enum.map(first.signals, & &1.type) == [
             "jido.chat.message.received",
             "jido.chat.normalization.failed",
             "jido.chat.message.received"
           ]

    assert Enum.map(first.signals, & &1.data["item_id"]) ==
             Enum.map(second.signals, & &1.data["item_id"])
  end

  defp message(stamp, text) do
    %{
      "envelope" => %{
        "sourceNumber" => "+15555550100",
        "sourceName" => "Tester",
        "timestamp" => stamp,
        "dataMessage" => %{"timestamp" => stamp, "message" => text}
      }
    }
  end
end
