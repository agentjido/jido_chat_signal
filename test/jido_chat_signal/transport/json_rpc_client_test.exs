defmodule Jido.Chat.Signal.Transport.JsonRpcClientTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.FileUpload
  alias Jido.Chat.Signal.Transport.JsonRpcClient

  test "polls receive through the JSON-RPC daemon" do
    test_pid = self()

    adapter = fn request ->
      body = Jason.decode!(request.body)
      send(test_pid, {:rpc_request, request.method, request.url, body, request.options})

      response =
        Req.Response.json(%{
          "jsonrpc" => "2.0",
          "id" => body["id"],
          "result" => [
            %{
              "envelope" => %{
                "sourceNumber" => "+15555550100",
                "timestamp" => 1_776_000_000,
                "dataMessage" => %{"timestamp" => 1_776_000_000, "message" => "hello"}
              }
            }
          ]
        })

      {request, %{response | status: 200}}
    end

    assert {:ok, [payload]} =
             JsonRpcClient.receive_messages(
               endpoint: "http://signal.test/api/v1/rpc",
               account: "+15555550101",
               receive_timeout_s: 2,
               max_messages: 5,
               req_options: [adapter: adapter]
             )

    assert %{"envelope" => %{"dataMessage" => %{"message" => "hello"}}} = payload

    assert_received {:rpc_request, :post, uri, body, options}
    assert URI.to_string(uri) == "http://signal.test/api/v1/rpc"
    assert options.receive_timeout == 15_000
    assert body["method"] == "receive"
    assert body["params"]["account"] == "+15555550101"
    assert body["params"]["timeout"] == 2
    assert body["params"]["maxMessages"] == 5
  end

  test "honors explicit HTTP receive timeout for receive polling" do
    test_pid = self()

    adapter = fn request ->
      send(test_pid, {:rpc_options, request.options})
      {request, %{Req.Response.json(%{"result" => []}) | status: 200}}
    end

    assert {:ok, []} =
             JsonRpcClient.receive_messages(
               endpoint: "http://signal.test/api/v1/rpc",
               receive_timeout_s: 30,
               http_receive_timeout_ms: 2_000,
               req_options: [adapter: adapter]
             )

    assert_received {:rpc_options, options}
    assert options.receive_timeout == 2_000
  end

  test "normalizes empty or non-envelope receive results to an empty list" do
    adapter = fn request ->
      body = Jason.decode!(request.body)

      response =
        Req.Response.json(%{
          "jsonrpc" => "2.0",
          "id" => body["id"],
          "result" => [%{"receiptMessage" => %{}}, nil]
        })

      {request, %{response | status: 200}}
    end

    assert {:ok, []} =
             JsonRpcClient.receive_messages(
               endpoint: "http://signal.test/api/v1/rpc",
               req_options: [adapter: adapter]
             )
  end

  test "returns JSON-RPC daemon errors" do
    adapter = fn request ->
      body = Jason.decode!(request.body)

      response =
        Req.Response.json(%{
          "jsonrpc" => "2.0",
          "id" => body["id"],
          "error" => %{"code" => -32_000, "message" => "already receiving"}
        })

      {request, %{response | status: 200}}
    end

    assert {:error,
            {:signal_rpc_error, 200, %{"code" => -32_000, "message" => "already receiving"}}} =
             JsonRpcClient.receive_messages(
               endpoint: "http://signal.test/api/v1/rpc",
               req_options: [adapter: adapter]
             )
  end

  test "sends local and data-backed attachments through JSON-RPC" do
    test_pid = self()

    adapter = fn request ->
      body = Jason.decode!(request.body)
      send(test_pid, {:rpc_body, body})

      {request,
       %{Req.Response.json(%{"result" => %{"timestamp" => 1_776_000_000}}) | status: 200}}
    end

    attachment =
      FileUpload.new(%{
        kind: :image,
        data: "R0lGODlhAQABAAAAACw=",
        filename: "tiny.gif",
        media_type: "image/gif"
      })

    assert {:ok, %{"timestamp" => 1_776_000_000}} =
             JsonRpcClient.send_message("+15555550100", "gif",
               endpoint: "http://signal.test/api/v1/rpc",
               attachments: [%{path: "/tmp/report.txt"}, attachment],
               req_options: [adapter: adapter]
             )

    assert_received {:rpc_body, body}

    assert body["params"]["attachments"] == [
             "/tmp/report.txt",
             "data:image/gif;filename=tiny.gif;base64,R0lGODlhAQABAAAAACw="
           ]
  end

  test "rejects remote attachments before JSON-RPC send" do
    assert {:error, {:unsupported_remote_attachment, "https://example.test/file.txt"}} =
             JsonRpcClient.send_message("+15555550100", "file",
               endpoint: "http://signal.test/api/v1/rpc",
               attachments: [%{url: "https://example.test/file.txt"}],
               req_options: [
                 adapter: fn request ->
                   flunk("unexpected JSON-RPC request: #{inspect(request)}")
                 end
               ]
             )
  end
end
