# Jido Chat Signal

[![Hex.pm](https://img.shields.io/hexpm/v/jido_chat_signal.svg)](https://hex.pm/packages/jido_chat_signal)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/jido_chat_signal/)
[![CI](https://github.com/agentjido/jido_chat_signal/actions/workflows/ci.yml/badge.svg)](https://github.com/agentjido/jido_chat_signal/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/jido_chat_signal.svg)](https://github.com/agentjido/jido_chat_signal/blob/main/LICENSE)
[![Website](https://img.shields.io/badge/website-jido.run-0f172a.svg)](https://jido.run)
[![Ecosystem](https://img.shields.io/badge/ecosystem-jido.run-0ea5e9.svg)](https://jido.run/ecosystem)
[![Discord](https://img.shields.io/badge/discord-join-5865F2.svg?logo=discord&logoColor=white)](https://jido.run/discord)

`jido_chat_signal` adapts Signal messages to the current Jido Chat V3 Signal,
adapter, and polling Source contracts through `signal-cli`.

## Local V3 status

The `release/v3` branch uses the sibling `../jido_chat` working tree for local
integration. It is not a published Hex dependency. Publication must select the
released Jido Chat V3 Hex package and repeat all package checks.

## Client and operations

Create an immutable client. Store the Signal account identity in
`credentials`. Store endpoint, executable, and transport policy in `config`.

```elixir
client = Jido.Chat.Client.new!(Jido.Chat.Signal.Adapter,
  id: "support-signal",
  credentials: %{account: System.get_env("SIGNAL_ACCOUNT")},
  config: [
    endpoint: System.get_env("SIGNAL_RPC_ENDPOINT"),
    executable: System.get_env("SIGNAL_CLI_PATH") || "signal-cli"
  ]
)

{:ok, result} = Jido.Chat.send_text(client, "+15555550100", "Hello from Jido")
message_id = result.data["result"]["id"]
```

The current native operations are `send_message` and `send_file`. All other
core operations are explicitly unsupported and stop before provider I/O.

## Inbound polling

`Jido.Chat.Signal.Source` is a receive-only polling Source for the shared Jido
Chat Sensor. It supports both the CLI and JSON-RPC transports. The Source passes
the account as a distinct private argument and passes only client config and
polling policy in the option list.

The Source normalizes complete receive batches into ordered
`MessageReceived` and `NormalizationFailed` Signals. Its key includes the
transport, account, endpoint, executable, and CLI config path so separate
provider identities do not share a polling process.

Jido Chat core owns the managed Sensor, Rooms, provider declarations, bridges,
storage, and application Signal Bus. This package starts no managed process
tree by itself.

## Transport choices

- `Jido.Chat.Signal.Transport.JsonRpcClient` uses a `signal-cli daemon --http`
  endpoint.
- `Jido.Chat.Signal.Transport.CliClient` runs one local `signal-cli` command
  for each send or receive request.

Signal does not provide an official bot API. Protect account files and local
daemon endpoints. Do not put account identity or raw provider data in Signal
payloads or logs.

## Checks

Run `mix test`, `mix test.contracts`, and `mix quality`. Live tests stay tagged
`:live` and excluded by default. They run only when `RUN_LIVE_SIGNAL_TESTS` and
the required local signal-cli values are set.

See `docs/v3-upgrade-validation.md` for current local evidence.
