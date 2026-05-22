# Jido Chat Signal

[![Hex.pm](https://img.shields.io/hexpm/v/jido_chat_signal.svg)](https://hex.pm/packages/jido_chat_signal)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/jido_chat_signal/)
[![CI](https://github.com/agentjido/jido_chat_signal/actions/workflows/ci.yml/badge.svg)](https://github.com/agentjido/jido_chat_signal/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/jido_chat_signal.svg)](https://github.com/agentjido/jido_chat_signal/blob/main/LICENSE)
[![Website](https://img.shields.io/badge/website-jido.run-0f172a.svg)](https://jido.run)
[![Ecosystem](https://img.shields.io/badge/ecosystem-jido.run-0ea5e9.svg)](https://jido.run/ecosystem)
[![Discord](https://img.shields.io/badge/discord-join-5865F2.svg?logo=discord&logoColor=white)](https://jido.run/discord)

`jido_chat_signal` adapts Signal messages to `Jido.Chat.Adapter` through [`signal-cli`](https://github.com/AsamK/signal-cli).

## Installation

```elixir
def deps do
  [
    {:jido_chat_signal, "~> 0.1"}
  ]
end
```

## signal-cli setup

Install and link/register `signal-cli`. For JSON-RPC send-only mode, start the daemon:

```bash
signal-cli -a +15555550100 daemon --http=127.0.0.1:8080
```

For production JSON-RPC polling ingress, start the daemon in manual receive mode:

```bash
signal-cli -a +15555550100 daemon --http=127.0.0.1:8080 --receive-mode manual --no-receive-stdout
```

For CLI live tests, the one-shot `signal-cli send` path is enough. For
multi-account mode, omit `-a` from the daemon command and set `SIGNAL_ACCOUNT`.

## Live testing

Set:

```bash
RUN_LIVE_SIGNAL_TESTS=true
SIGNAL_TRANSPORT=cli
SIGNAL_ACCOUNT=+15555550100
SIGNAL_TEST_RECIPIENT=+15555550101
```

Run:

```bash
mix test --include live
```

The live test sends a text message, a small file attachment, a GIF attachment,
and a quoted reply.
Use `SIGNAL_TRANSPORT=json_rpc` when testing against `signal-cli daemon --http`.
In that mode, also set `SIGNAL_RPC_ENDPOINT`.

## Ingress

For production, prefer JSON-RPC polling against `signal-cli daemon --http`:

```elixir
opts: %{
  ingress: %{
    mode: "rpc_polling",
    endpoint: System.fetch_env!("SIGNAL_RPC_ENDPOINT"),
    account: System.fetch_env!("SIGNAL_ACCOUNT"),
    receive_timeout_s: 3,
    max_messages: 10,
    poll_interval_ms: 1_000
  }
}
```

This calls the daemon's JSON-RPC `receive` method on each poll. The daemon must
run with `--receive-mode manual`; otherwise Signal may already be receiving and
the explicit `receive` RPC can be rejected.

For local CLI-only setups, use adapter-owned CLI polling:

```elixir
opts: %{
  ingress: %{
    mode: "polling",
    account: System.fetch_env!("SIGNAL_ACCOUNT"),
    receive_timeout_s: 1,
    max_messages: 10,
    poll_interval_ms: 1_000
  }
}
```

Both polling modes emit each envelope through the bridge `sink_mfa` and let the
runtime call `Jido.Chat.Signal.Adapter.transform_incoming/1`.

`signal-cli daemon --http` also exposes `GET /api/v1/events` as a Server-Sent
Events stream. The RPC poller is simpler to supervise and keeps receive ownership
inside the bridge runtime.
