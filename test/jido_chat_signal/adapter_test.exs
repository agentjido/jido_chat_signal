defmodule Jido.Chat.Signal.AdapterTest do
  use ExUnit.Case, async: true
  import Jido.Chat.AdapterTestKit.Assertions
  alias Jido.Chat.AdapterTestKit.Factories
  alias Jido.Chat.{Capabilities, FileUpload}
  alias Jido.Chat.Errors.Contract
  alias Jido.Chat.Operations.Definitions
  alias Jido.Chat.Signal.{Adapter, Identity, PostMessage, SendMessage}
  alias Jido.Signal.{Context, Trace}

  defmodule FakeTransport do
    @behaviour Jido.Chat.Signal.Transport
    def send_message(target, text, opts) do
      if pid = opts[:test_pid], do: send(pid, {:signal_send, target, text, opts})

      case opts[:failure] do
        true -> {:error, {:private_error, "private-token"}}
        _ -> {:ok, %{"timestamp" => 1_776_000_000}}
      end
    end

    def list_groups(_opts), do: {:ok, []}
  end

  defp test_binding(opts \\ []) do
    {:ok, value} =
      Jido.Chat.bind(
        Adapter,
        [id: "signal-1", transport: FakeTransport, test_pid: self()] ++ opts
      )

    value
  end

  defp message(stamp \\ 1_776_000_000, text \\ "hello") do
    %{
      "envelope" => %{
        "sourceNumber" => "+15555550100",
        "sourceName" => "Tester",
        "timestamp" => stamp,
        "dataMessage" => %{"timestamp" => stamp, "message" => text}
      }
    }
  end

  test "sends a typed request through one captured signal-cli transport" do
    binding = test_binding()

    request =
      SendMessage.new!(%{
        "request_id" => "send-1",
        "room_id" => "+15555550100",
        "text" => "hello"
      })

    result = assert_operation_result(Jido.Chat.execute(binding, request))
    assert result.data["result"]["id"] == "1776000000"
    assert_received {:signal_send, "+15555550100", "hello", _}
    refute_received {:signal_send, _, _, _}
    assert {:ok, ^result} = Jido.Chat.execute(binding, request)
    refute_received {:signal_send, _, _, _}
    assert :ok = assert_json_round_trip(result)
  end

  test "declares native delivery and exact finite core fallback capabilities" do
    assert :ok = assert_capability_coherence(Adapter)
    capabilities = Jido.Chat.Adapter.capabilities(Adapter)

    assert Map.take(capabilities, [:send_message, :send_file, :post_message, :stream]) ==
             %{
               send_message: :native,
               send_file: :native,
               post_message: :native,
               stream: :fallback
             }

    assert Capabilities.channel_capabilities(Adapter) == [
             :text,
             :image,
             :audio,
             :video,
             :file,
             :multi_file,
             :streaming
           ]

    refute function_exported?(Adapter, :transform_incoming, 1)
  end

  test "posts private file references through the transport attachment path" do
    binding = test_binding()
    file = FileUpload.new(%{kind: :file, path: "/tmp/report.txt", filename: "report.txt"})
    assert {:ok, ref} = Jido.Chat.put_resource(binding, "file", file)

    request =
      PostMessage.new!(%{
        "request_id" => "file-1",
        "room_id" => "+15555550100",
        "content" => %{"kind" => "media", "resource_ref" => ref, "caption" => "file caption"}
      })

    result = assert_operation_result(Jido.Chat.execute(binding, request))
    assert result.data["result"]["id"] == "1776000000"
    assert_received {:signal_send, "+15555550100", "file caption", opts}
    assert [%FileUpload{path: "/tmp/report.txt"}] = opts[:attachments]
    refute Jason.encode!(Jido.Signal.to_map(result)) =~ "/tmp/report.txt"
  end

  test "normalizes receive notification with independent quote identity and private media" do
    payload = message()

    attachments = [
      %{"contentType" => "image/png", "filename" => "image.png", "size" => 123},
      %{"filename" => " ", "fileName" => "fallback.png", "size" => 456},
      %{"content_type" => " ", "fileName" => "archive.unknown", "size" => 789},
      %{
        "contentType" => " Application/PDF; Charset=binary ",
        "filename" => "misleading.png",
        "size" => 1_000
      },
      %{"contentType" => "not-a-mime", "filename" => "invalid-fallback.png", "size" => 1_001}
    ]

    payload = put_in(payload, ["envelope", "dataMessage", "attachments"], attachments)

    payload =
      put_in(payload, ["envelope", "dataMessage", "quote"], %{
        "id" => 1_775_999_999,
        "text" => "parent"
      })

    binding = test_binding()
    delivery = assert_delivery(binding, Jido.Chat.normalize_event(binding, payload))
    [signal] = delivery.signals
    assert signal.data["room_id"] == "+15555550100"
    assert signal.data["reply_to_id"] == "1775999999"
    assert signal.data["text"] == "hello"
    assert Enum.map(signal.data["media"], & &1["kind"]) == ~w(image image file file image)

    assert Enum.map(signal.data["media"], & &1["name"]) ==
             ~w(image.png fallback.png archive.unknown misleading.png invalid-fallback.png)

    assert Enum.map(signal.data["media"], & &1["media_type"]) == [
             "image/png",
             nil,
             nil,
             "application/pdf",
             nil
           ]

    assert Enum.zip(signal.data["media"], attachments)
           |> Enum.all?(fn {media, raw} ->
             Jido.Chat.resolve_resource(binding, media["resource_ref"]) == {:ok, raw}
           end)

    assert :ok = assert_json_round_trip(signal)
    refute Jason.encode!(Jido.Signal.to_map(signal)) =~ "size"
  end

  test "non-message and empty envelopes produce typed failure facts without blank messages" do
    binding = test_binding()

    for input <- [
          %{"envelope" => %{"receiptMessage" => %{}}},
          message(1, ""),
          nil,
          %{"envelope" => %{"dataMessage" => "bad"}}
        ] do
      delivery = assert_delivery(binding, Jido.Chat.normalize_event(binding, input))
      assert [%Jido.Signal{type: "jido.chat.normalization.failed"}] = delivery.signals
    end
  end

  test "zero/one/many receive items keep stable identities and complete order" do
    binding = test_binding()
    assert {:ok, %{signals: []}} = Jido.Chat.normalize_event(binding, [])
    inputs = [message(1, "first"), nil, message(2, "last")]
    first = assert_delivery(binding, Jido.Chat.normalize_event(binding, inputs))
    second = assert_delivery(binding, Jido.Chat.normalize_event(binding, inputs))
    assert first.id == second.id

    assert Enum.map(first.signals, & &1.data["item_id"]) ==
             Enum.map(second.signals, & &1.data["item_id"])

    assert Enum.map(first.signals, & &1.type) == [
             "jido.chat.message.received",
             "jido.chat.normalization.failed",
             "jido.chat.message.received"
           ]

    assert Enum.map(first.signals, & &1.data["text"]) == ["first", nil, "last"]

    assert {:error, %Contract{code: :too_many_signals}} =
             Jido.Chat.normalize_event(binding, List.duplicate(message(), 101))

    assert {:error, %Contract{code: :too_many_failures}} =
             Jido.Chat.normalize_event(binding, List.duplicate(nil, 21))
  end

  test "JSON-RPC and direct forms use the same mapper; group routing stays separate" do
    binding = test_binding()

    direct =
      put_in(message(), ["envelope", "dataMessage", "groupInfo"], %{"groupId" => "group/1"})

    rpc = %{"params" => %{"result" => direct}}
    assert {:ok, one} = Jido.Chat.normalize_event(binding, direct)
    assert {:ok, two} = Jido.Chat.normalize_event(binding, rpc)
    assert one.id == two.id
    assert hd(one.signals).data == hd(two.signals).data
    assert hd(one.signals).data["room_id"] == "group:group/1"
    assert hd(one.signals).data["thread_id"] == "group/1"

    assert hd(one.signals).subject ==
             Identity.conversation_subject(binding.id, "group:group/1")

    assert {:ok, other} = Jido.Chat.bind(Adapter, id: "other")
    assert {:ok, other_delivery} = Jido.Chat.normalize_event(other, direct)
    refute one.id == other_delivery.id
    refute hd(one.signals).source == hd(other_delivery.signals).source
  end

  @matrix Path.expand("../../../jido_chat/docs/migration/adapter-matrix.json", __DIR__)
          |> File.read!()
          |> Jason.decode!()
  @row Enum.find(@matrix["adapters"], &(&1["package"] == "jido_chat_signal"))

  for {_type, {_definition, operation, _fields, _shape, _schema}} <-
        Definitions.all() do
    test "#{operation}: declared operation selects its exact native/fallback/unsupported result" do
      operation = unquote(operation)
      binding = test_binding()
      request = Factories.operation_request(binding, operation)
      result = assert_operation_result(Jido.Chat.execute(binding, request))
      support = Jido.Chat.Adapter.capabilities(Adapter)[operation]
      assert Atom.to_string(support) == @row["operation_support"][Atom.to_string(operation)]

      if support == :unsupported do
        assert result.type == "jido.chat.operation.failed"
        assert result.data["code"] == "unsupported"
        refute_received {:signal_send, _, _, _}
      else
        assert result.type == "jido.chat.operation.completed"

        if operation in [:send_message, :send_file, :post_message, :post_channel_message, :stream] do
          assert_received {:signal_send, "room/1", _, _}
          refute_received {:signal_send, _, _, _}
        else
          refute_received {:signal_send, _, _, _}
        end
      end

      assert {:ok, ^result} = Jido.Chat.execute(binding, request)
      refute_received {:signal_send, _, _, _}
      assert Context.get(result, "causationid") == request.id
      assert Trace.get(result).trace_id == Trace.get(request).trace_id
      assert :ok = assert_json_round_trip(result)
    end
  end

  test "automatic and subscription notifications share the same delivery identity" do
    binding = test_binding()
    direct = message()
    automatic = %{"params" => direct}
    subscription = %{"params" => %{"result" => direct}}

    deliveries =
      Enum.map([direct, automatic, subscription], fn input ->
        assert_delivery(binding, Jido.Chat.normalize_event(binding, input))
      end)

    assert deliveries |> Enum.map(& &1.id) |> Enum.uniq() |> length() == 1
    assert deliveries |> Enum.map(&hd(&1.signals).data) |> Enum.uniq() |> length() == 1
  end

  test "sent sync messages use the destination conversation and mark the sender as self" do
    binding = test_binding()

    input = %{
      "envelope" => %{
        "sourceUuid" => "self-account",
        "timestamp" => 1,
        "syncMessage" => %{
          "sentMessage" => %{
            "destinationUuid" => "peer-account",
            "timestamp" => 1,
            "message" => "hello"
          }
        }
      }
    }

    delivery = assert_delivery(binding, Jido.Chat.normalize_event(binding, input))
    assert hd(delivery.signals).data["room_id"] == "peer-account"
    assert hd(delivery.signals).data["sender"] == %{"id" => "self-account", "is_self" => true}
  end

  test "unverified group master keys do not become public conversation IDs" do
    binding = test_binding()

    input =
      put_in(message(), ["envelope", "dataMessage", "groupV2"], %{
        "masterKey" => "private-master-key"
      })

    delivery = assert_delivery(binding, Jido.Chat.normalize_event(binding, input))
    assert [%Jido.Signal{type: "jido.chat.normalization.failed"} = failure] = delivery.signals
    refute Jason.encode!(Jido.Signal.to_map(failure)) =~ "private-master-key"
  end

  test "missing provider identity uses a stable digest without merging distinct invalid items" do
    binding = test_binding()

    one =
      assert_delivery(
        binding,
        Jido.Chat.normalize_event(binding, %{
          "envelope" => %{"dataMessage" => %{"message" => "one"}}
        })
      )

    two =
      assert_delivery(
        binding,
        Jido.Chat.normalize_event(binding, %{
          "envelope" => %{"dataMessage" => %{"message" => "two"}}
        })
      )

    refute one.id == two.id
  end

  test "provider failure is typed and has no private error input" do
    binding = test_binding(failure: true)

    result =
      assert_operation_result(
        Jido.Chat.execute(
          binding,
          SendMessage.new!(%{"request_id" => "failure", "room_id" => "room-1", "text" => "hello"})
        )
      )

    assert result.type == "jido.chat.operation.failed"
    assert result.data["code"] == "provider_failure"
    refute Jason.encode!(Jido.Signal.to_map(result)) =~ "private-token"
    assert_received {:signal_send, "room-1", "hello", _}
    refute_received {:signal_send, _, _, _}
  end

  for {name, support} <- @row["event_support"] do
    test "#{name} matches frozen #{support} without inferred events" do
      input =
        if unquote(name) == "MessageReceived",
          do: message(),
          else: %{"envelope" => %{unquote(name) => %{}}}

      assert {:ok, %{signals: [fact]}} = Jido.Chat.normalize_event(test_binding(), input)

      expected =
        if unquote(name) == "MessageReceived",
          do: "jido.chat.message.received",
          else: "jido.chat.normalization.failed"

      assert fact.type == expected
      assert_json_round_trip(fact)
    end
  end

  test "an item keeps its identity when its batch position changes" do
    binding = test_binding()
    assert {:ok, %{signals: [one]}} = Jido.Chat.normalize_event(binding, message(2))

    assert {:ok, %{signals: [_, many]}} =
             Jido.Chat.normalize_event(binding, [message(1), message(2)])

    assert one.data["item_id"] == many.data["item_id"]
  end

  test "all four complete limits reject and cancel newly created media" do
    binding = test_binding()
    media = %{"filename" => "private.bin", "path" => "/private/media"}

    make = fn stamp, text ->
      put_in(message(stamp, text), ["envelope", "dataMessage", "attachments"], [media])
    end

    cases = [
      {make.(1, String.duplicate("x", 262_145)), :signal_too_large},
      {Enum.map(1..101, &make.(&1, "body")), :too_many_signals},
      {List.duplicate(nil, 21), :too_many_failures},
      {Enum.map(1..6, &make.(&1, String.duplicate("x", 200_000))), :delivery_too_large}
    ]

    for {input, expected} <- cases do
      assert {:error, %{code: ^expected}} = Jido.Chat.normalize_event(binding, input)

      refute Enum.any?(:ets.tab2list(binding.resources), fn
               {{:resource, _}, _, _, _, _, :active} -> true
               _ -> false
             end)
    end

    invalid = put_in(message(), ["envelope", "dataMessage", "attachments"], [media, :invalid])

    assert {:ok, %{signals: [%{type: "jido.chat.normalization.failed"}]}} =
             Jido.Chat.normalize_event(binding, invalid)

    refute Enum.any?(:ets.tab2list(binding.resources), fn
             {{:resource, _}, _, _, _, _, :active} -> true
             _ -> false
           end)
  end

  test "media owner, cancellation and expiry remain private" do
    binding = test_binding()

    input =
      put_in(message(), ["envelope", "dataMessage", "attachments"], [%{"path" => "/private/file"}])

    assert {:ok, %{signals: [fact]}} = Jido.Chat.normalize_event(binding, input)
    [item] = fact.data["media"]
    ref = item["resource_ref"]
    assert {:ok, media} = Jido.Chat.resolve_resource(binding, ref)
    assert media["path"] == "/private/file"

    assert {:error, %{code: :resource_owner_mismatch}} =
             Task.async(fn -> Jido.Chat.resolve_resource(binding, ref) end) |> Task.await()

    assert :ok = Jido.Chat.cancel_resource(binding, ref)
    assert {:error, %{code: :resource_cancelled}} = Jido.Chat.resolve_resource(binding, ref)
    {:ok, expired} = Jido.Chat.put_resource(binding, "media", media, ttl_ms: 0)
    assert {:error, %{code: :resource_expired}} = Jido.Chat.resolve_resource(binding, expired)
    assert_json_round_trip(fact)
    refute Jason.encode!(Jido.Signal.to_map(fact)) =~ "/private/file"
  end
end
