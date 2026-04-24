# Jido Chat Signal

`jido_chat_signal` adapts Signal messages to `Jido.Chat.Adapter` through [`signal-cli`](https://github.com/AsamK/signal-cli).

## signal-cli setup

Install and link/register `signal-cli`, then start the daemon:

```bash
signal-cli -a +15555550100 daemon --http=127.0.0.1:8080
```

For multi-account mode, omit `-a` and set `SIGNAL_ACCOUNT`.

## Live testing

Set:

```bash
RUN_LIVE_SIGNAL_TESTS=true
SIGNAL_RPC_ENDPOINT=http://127.0.0.1:8080/api/v1/rpc
SIGNAL_ACCOUNT=+15555550100
SIGNAL_TEST_RECIPIENT=+15555550101
```

Run:

```bash
mix test --include live
```

## Ingress

`signal-cli daemon --http` exposes `GET /api/v1/events` as a Server-Sent Events stream. The adapter normalizes `receive` envelopes, and a runtime listener should consume that stream and pass each payload to `Jido.Chat.Signal.Adapter.transform_incoming/1`.
