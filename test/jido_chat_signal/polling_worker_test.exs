defmodule Jido.Chat.Signal.PollingWorkerTest do
  use ExUnit.Case, async: false

  alias Jido.Chat.Signal.{Adapter, PollingWorker}
  alias Jido.Chat.Signal.Transport.{CliClient, JsonRpcClient}

  defmodule PollingReceiver do
    def receive_messages(opts) do
      test_pid = Keyword.fetch!(opts, :test_pid)
      responses_agent = Keyword.fetch!(opts, :responses_agent)
      send(test_pid, {:receive_call, opts})

      Agent.get_and_update(responses_agent, fn
        [next | rest] -> {next, rest}
        [] -> {{:ok, []}, []}
      end)
    end
  end

  defmodule OkSink do
    def emit(test_pid, payload, opts) do
      send(test_pid, {:sink_emit, payload, opts})
      {:ok, :accepted}
    end
  end

  defmodule ErrorSink do
    def emit(test_pid, payload, opts) do
      send(test_pid, {:sink_emit, payload, opts})
      {:error, :sink_failed}
    end
  end

  defmodule SelectiveSink do
    def emit(test_pid, %{"id" => "bad"} = payload, opts) do
      send(test_pid, {:sink_emit, payload, opts})
      {:error, :sink_failed}
    end

    def emit(test_pid, payload, opts) do
      send(test_pid, {:sink_emit, payload, opts})
      {:ok, :accepted}
    end
  end

  test "adapter listener_child_specs/2 returns expected polling specs" do
    assert {:ok, []} = Adapter.listener_child_specs("bridge_signal", ingress: %{})
    assert {:ok, []} = Adapter.listener_child_specs("bridge_signal", ingress: %{mode: "manual"})

    assert {:error, :invalid_sink_mfa} =
             Adapter.listener_child_specs("bridge_signal", ingress: %{mode: "polling"})

    assert {:ok, [spec]} =
             Adapter.listener_child_specs("bridge_signal",
               ingress: %{
                 mode: "polling",
                 account: "+15555550101",
                 receive_timeout_s: 2,
                 max_messages: 10,
                 receiver: PollingReceiver
               },
               sink_mfa: {OkSink, :emit, [self()]}
             )

    assert spec.id == {:signal_polling_worker, "bridge_signal"}
    assert %{start: {PollingWorker, :start_link, [worker_opts]}} = spec
    assert worker_opts[:receiver] == PollingReceiver
    assert worker_opts[:receiver_opts][:account] == "+15555550101"
  end

  test "adapter listener_child_specs/2 selects CLI or JSON-RPC polling receivers by mode" do
    assert {:ok, [cli_spec]} =
             Adapter.listener_child_specs("bridge_signal_cli",
               ingress: %{mode: "cli_polling"},
               sink_mfa: {OkSink, :emit, [self()]}
             )

    assert %{start: {PollingWorker, :start_link, [cli_opts]}} = cli_spec
    assert cli_opts[:receiver] == CliClient

    assert {:ok, [rpc_spec]} =
             Adapter.listener_child_specs("bridge_signal_rpc",
               ingress: %{
                 mode: "rpc_polling",
                 endpoint: "http://127.0.0.1:8080/api/v1/rpc",
                 account: "+15555550101",
                 receive_timeout_s: 3,
                 max_messages: 5
               },
               sink_mfa: {OkSink, :emit, [self()]}
             )

    assert %{start: {PollingWorker, :start_link, [rpc_opts]}} = rpc_spec
    assert rpc_opts[:receiver] == JsonRpcClient
    assert rpc_opts[:receiver_opts][:endpoint] == "http://127.0.0.1:8080/api/v1/rpc"
    assert rpc_opts[:receiver_opts][:account] == "+15555550101"
    assert rpc_opts[:receiver_opts][:receive_timeout_s] == 3
    assert rpc_opts[:receiver_opts][:max_messages] == 5
  end

  test "polling worker emits received envelopes through sink" do
    {:ok, responses_agent} =
      Agent.start_link(fn ->
        [
          {:ok, [%{"envelope" => %{"timestamp" => 1_776_000_000}}]},
          {:ok, []}
        ]
      end)

    {:ok, _pid} =
      start_supervised(
        {PollingWorker,
         bridge_id: "bridge_signal",
         sink_mfa: {OkSink, :emit, [self()]},
         receiver: PollingReceiver,
         receiver_opts: [test_pid: self(), responses_agent: responses_agent],
         poll_interval_ms: 10,
         max_backoff_ms: 50}
      )

    assert_receive {:receive_call, _opts}, 200
    assert_receive {:sink_emit, %{"envelope" => %{"timestamp" => 1_776_000_000}}, sink_opts}, 200
    assert sink_opts[:mode] == :payload

    assert_receive {:receive_call, _opts}, 400
  end

  test "polling worker backs off when the sink rejects a payload" do
    {:ok, responses_agent} =
      Agent.start_link(fn ->
        [
          {:ok, [%{"envelope" => %{"timestamp" => 1_776_000_001}}]},
          {:ok, []}
        ]
      end)

    {:ok, _pid} =
      start_supervised(
        {PollingWorker,
         bridge_id: "bridge_signal",
         sink_mfa: {ErrorSink, :emit, [self()]},
         receiver: PollingReceiver,
         receiver_opts: [test_pid: self(), responses_agent: responses_agent],
         poll_interval_ms: 10,
         max_backoff_ms: 50}
      )

    assert_receive {:receive_call, _opts}, 200
    assert_receive {:sink_emit, %{"envelope" => %{"timestamp" => 1_776_000_001}}, _sink_opts}, 200
    assert_receive {:receive_call, _opts}, 400
  end

  test "polling worker still emits later messages from a drained batch after a sink error" do
    {:ok, responses_agent} =
      Agent.start_link(fn ->
        [
          {:ok, [%{"id" => "bad"}, %{"id" => "good"}]},
          {:ok, []}
        ]
      end)

    {:ok, _pid} =
      start_supervised(
        {PollingWorker,
         bridge_id: "bridge_signal",
         sink_mfa: {SelectiveSink, :emit, [self()]},
         receiver: PollingReceiver,
         receiver_opts: [test_pid: self(), responses_agent: responses_agent],
         poll_interval_ms: 10,
         max_backoff_ms: 50}
      )

    assert_receive {:receive_call, _opts}, 200
    assert_receive {:sink_emit, %{"id" => "bad"}, _sink_opts}, 200
    assert_receive {:sink_emit, %{"id" => "good"}, _sink_opts}, 200
    assert_receive {:receive_call, _opts}, 400
  end
end
