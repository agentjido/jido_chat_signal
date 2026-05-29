defmodule Jido.Chat.Signal.AdapterTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.Adapter, as: ChatAdapter
  alias Jido.Chat.{Capabilities, PostPayload}
  alias Jido.Chat.Signal.Adapter

  defmodule FakeTransport do
    @behaviour Jido.Chat.Signal.Transport

    def send_message(target, text, opts) do
      if pid = opts[:test_pid], do: send(pid, {:signal_send, target, text, opts})
      {:ok, %{"timestamp" => 1_776_000_000}}
    end

    def list_groups(_opts), do: {:ok, []}
  end

  test "sends a message through signal-cli transport" do
    assert {:ok, response} =
             Adapter.send_message("+15555550100", "hello", transport: FakeTransport)

    assert response.external_message_id == 1_776_000_000
    assert response.message_id == "1776000000"
  end

  test "declares only delivery capabilities it can satisfy" do
    assert :ok = ChatAdapter.validate_capabilities(Jido.Chat.Signal.Adapter)

    assert Capabilities.channel_capabilities(Jido.Chat.Signal.Adapter) == [
             :text,
             :image,
             :audio,
             :video,
             :file,
             :multi_file,
             :streaming
           ]
  end

  test "posts files through the transport attachment path" do
    payload =
      PostPayload.text("file caption",
        files: [%{kind: :file, path: "/tmp/report.txt", filename: "report.txt"}]
      )

    assert {:ok, response} =
             ChatAdapter.post_message(Jido.Chat.Signal.Adapter, "+15555550100", payload,
               transport: FakeTransport,
               test_pid: self()
             )

    assert response.external_message_id == 1_776_000_000
    assert response.message_id == "1776000000"
    assert [%{path: "/tmp/report.txt"}] = response.metadata.attachments

    assert_received {:signal_send, "+15555550100", "file caption", opts}
    assert [%Jido.Chat.FileUpload{path: "/tmp/report.txt"}] = opts[:attachments]
  end

  test "normalizes signal-cli receive notification with quote and media" do
    payload = %{
      "envelope" => %{
        "sourceNumber" => "+15555550100",
        "sourceName" => "Tester",
        "timestamp" => 1_776_000_000,
        "dataMessage" => %{
          "timestamp" => 1_776_000_000,
          "message" => "hello",
          "quote" => %{"id" => 1_775_999_999, "author" => "+15555550101", "text" => "parent"},
          "attachments" => [
            %{"contentType" => "image/png", "filename" => "image.png", "size" => 123}
          ]
        }
      }
    }

    assert {:ok, incoming} = Adapter.transform_incoming(payload)
    assert incoming.external_room_id == "+15555550100"
    assert incoming.external_reply_to_id == 1_775_999_999
    assert incoming.text == "hello"

    assert [%Jido.Chat.Media{kind: :image, filename: "image.png", size_bytes: 123}] =
             incoming.media
  end

  test "rejects non-message signal envelopes instead of creating blank messages" do
    payload = %{
      "envelope" => %{
        "sourceNumber" => "+15555550100",
        "timestamp" => 1_776_000_000,
        "receiptMessage" => %{"when" => 1_776_000_000}
      }
    }

    assert {:error, :unsupported_envelope} = Adapter.transform_incoming(payload)
  end

  test "rejects empty data messages instead of creating blank messages" do
    payload = %{
      "envelope" => %{
        "sourceNumber" => "+15555550100",
        "timestamp" => 1_776_000_000,
        "dataMessage" => %{"timestamp" => 1_776_000_000, "message" => ""}
      }
    }

    assert {:error, :empty_data_message} = Adapter.transform_incoming(payload)
  end
end
