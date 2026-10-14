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
    def emit(
          test_pid,
          %Jido.Chat.Delivery{signals: [%Jido.Signal{data: %{"message_id" => "bad"}}]} = payload,
          opts
        ) do
      send(test_pid, {:sink_emit, payload, opts})
      {:error, :sink_failed}
    end

    def emit(test_pid, payload, opts) do
      send(test_pid, {:sink_emit, payload, opts})
      {:ok, :accepted}
    end
  end

  defp test_binding do
    {:ok, value} = Jido.Chat.bind(Adapter, id: "signal-polling")
    value
  end

  defp message(stamp) do
    %{
      "envelope" => %{
        "sourceNumber" => "+15555550100",
        "timestamp" => stamp,
        "dataMessage" => %{"timestamp" => stamp, "message" => "hello"}
      }
    }
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

  test "listener setup uses the captured binding transport settings" do
    {:ok, binding} =
      Jido.Chat.bind(Adapter,
        id: "captured",
        account: "+15555550102",
        endpoint: "http://captured.test/rpc",
        executable: "captured-cli"
      )

    assert {:ok, [spec]} =
             Adapter.listener_child_specs("captured",
               binding: binding,
               ingress: %{mode: "rpc_polling"},
               sink_mfa: {OkSink, :emit, [self()]}
             )

    %{start: {PollingWorker, :start_link, [opts]}} = spec
    assert opts[:receiver_opts][:account] == "+15555550102"
    assert opts[:receiver_opts][:endpoint] == "http://captured.test/rpc"
    assert opts[:receiver_opts][:executable] == "captured-cli"
    assert opts[:binding] == binding
  end

  test "polling worker emits received envelopes through sink" do
    {:ok, responses_agent} =
      Agent.start_link(fn ->
        [
          {:ok, [message(1_776_000_000)]},
          {:ok, []}
        ]
      end)

    {:ok, _pid} =
      start_supervised(
        {PollingWorker,
         binding: test_binding(),
         bridge_id: "bridge_signal",
         sink_mfa: {OkSink, :emit, [self()]},
         receiver: PollingReceiver,
         receiver_opts: [test_pid: self(), responses_agent: responses_agent],
         poll_interval_ms: 10,
         max_backoff_ms: 50}
      )

    assert_receive {:receive_call, _opts}, 200

    assert_receive {:sink_emit,
                    %Jido.Chat.Delivery{
                      signals: [%Jido.Signal{data: %{"message_id" => "1776000000"}}]
                    }, sink_opts},
                   200

    refute Keyword.has_key?(sink_opts, :mode)

    assert_receive {:receive_call, _opts}, 400
  end

  test "polling worker backs off when the sink rejects a payload" do
    {:ok, responses_agent} =
      Agent.start_link(fn ->
        [
          {:ok, [message(1_776_000_001)]},
          {:ok, []}
        ]
      end)

    {:ok, _pid} =
      start_supervised(
        {PollingWorker,
         binding: test_binding(),
         bridge_id: "bridge_signal",
         sink_mfa: {ErrorSink, :emit, [self()]},
         receiver: PollingReceiver,
         receiver_opts: [test_pid: self(), responses_agent: responses_agent],
         poll_interval_ms: 10,
         max_backoff_ms: 50}
      )

    assert_receive {:receive_call, _opts}, 200

    assert_receive {:sink_emit,
                    %Jido.Chat.Delivery{
                      signals: [%Jido.Signal{data: %{"message_id" => "1776000001"}}]
                    }, _sink_opts},
                   200

    assert_receive {:receive_call, _opts}, 400
  end

  test "polling worker still emits later messages from a drained batch after a sink error" do
    {:ok, responses_agent} =
      Agent.start_link(fn ->
        [
          {:ok, [message("bad"), message("good")]},
          {:ok, []}
        ]
      end)

    {:ok, _pid} =
      start_supervised(
        {PollingWorker,
         binding: test_binding(),
         bridge_id: "bridge_signal",
         sink_mfa: {SelectiveSink, :emit, [self()]},
         receiver: PollingReceiver,
         receiver_opts: [test_pid: self(), responses_agent: responses_agent],
         poll_interval_ms: 10,
         max_backoff_ms: 50}
      )

    assert_receive {:receive_call, _opts}, 200

    assert_receive {:sink_emit,
                    %Jido.Chat.Delivery{signals: [%Jido.Signal{data: %{"message_id" => "bad"}}]},
                    _sink_opts},
                   200

    assert_receive {:sink_emit,
                    %Jido.Chat.Delivery{signals: [%Jido.Signal{data: %{"message_id" => "good"}}]},
                    _sink_opts},
                   200

    assert_receive {:receive_call, _opts}, 400
  end

  defmodule FailingSink do
    def emit(test_pid, mode, delivery, _opts) do
      send(test_pid, {:attempted, delivery})

      case mode do
        :error -> {:error, :rejected}
        :raise -> raise "private-sink-error"
        :throw -> throw(:private_sink_error)
        :exit -> exit(:private_sink_error)
        :invalid -> :invalid
      end
    end
  end

  for mode <- [:error, :raise, :throw, :exit, :invalid] do
    test "sink #{mode} is reported, keeps the worker alive and retains polling backoff" do
      {:ok, responses} = Agent.start_link(fn -> [{:ok, [message(1), message(2)]}] end)
      interval = 60_000

      state = %{
        bridge_id: "test",
        binding: test_binding(),
        receiver: PollingReceiver,
        receiver_opts: [test_pid: self(), responses_agent: responses],
        sink_mfa: {FailingSink, :emit, [self(), unquote(mode)]},
        sink_opts: [],
        backoff_ms: interval,
        poll_interval_ms: interval,
        max_backoff_ms: interval * 4,
        last_result: nil
      }

      assert {:noreply, after_poll} = PollingWorker.handle_info(:poll, state)
      assert after_poll.backoff_ms == interval * 2
      assert {:error, {:sink_failures, [_, _]}} = after_poll.last_result
      assert_receive {:attempted, %{signals: [%{data: %{"message_id" => "1"}}]}}
      assert_receive {:attempted, %{signals: [%{data: %{"message_id" => "2"}}]}}
      refute_receive {:attempted, _}
      refute Map.has_key?(after_poll, :checkpoint)
    end
  end

  test "a complete limit breach causes zero sink calls" do
    input =
      put_in(message(3), ["envelope", "dataMessage", "message"], String.duplicate("x", 262_145))

    {:ok, responses} = Agent.start_link(fn -> [{:ok, [input]}] end)

    state = %{
      bridge_id: "test",
      binding: test_binding(),
      receiver: PollingReceiver,
      receiver_opts: [test_pid: self(), responses_agent: responses],
      sink_mfa: {OkSink, :emit, [self()]},
      sink_opts: [],
      backoff_ms: 60_000,
      poll_interval_ms: 60_000,
      max_backoff_ms: 120_000,
      last_result: nil
    }

    assert {:noreply, after_poll} = PollingWorker.handle_info(:poll, state)
    assert {:error, {:sink_failures, [%{code: :signal_too_large}]}} = after_poll.last_result
    refute_receive {:sink_emit, _, _}
  end
end
