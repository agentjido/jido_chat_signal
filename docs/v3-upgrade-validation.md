# Jido Chat V3 validation: Signal

Date: 2026-11-16 (America/Chicago).

## Scope

The Signal `release/v3` branch is validated against the current sibling
`../jido_chat` working tree. The core uses consolidated Jido V3. This is local
integration evidence. It is not Hex publication or live provider evidence.

The adapter keeps these V3 boundaries:

- one stateless `Jido.Chat.Adapter` for send operations;
- strict native or unsupported capability values;
- typed core request, result, and inbound Signals;
- one `Jido.Chat.Sensor.Source` for host-started receive polling;
- Signal account identity in `Client.credentials`;
- endpoint, executable, and transport policy in `Client.config`;
- provider transport in `Client.transport`;
- managed Room and provider runtime in Jido Chat core.

## Current migration changes

- Replaced the fixed remote Jido Chat source with `path: "../jido_chat"` for
  every local environment.
- Removed the stale Jido Chat lock entry and selected the consolidated Jido V3
  commit required by the local core.
- Replaced the removed credential-merging client helper in operations and
  Source polling with explicit client fields.
- Moved the account identity to a distinct transport argument. Generic
  transport options contain adapter config and polling policy but no account or
  credentials key.
- Strengthened Source identity with transport, account, endpoint, executable,
  and CLI config path.
- Removed the unused `list_groups` transport surface and made batch list
  construction linear.
- Added direct account separation, Source error, attachment, CLI, JSON-RPC,
  normalization, limit, and provider-error tests.
- Replaced stale binding, capability, source-pin, and separate-runtime-owner
  documentation with the current Jido Chat V3 contract.

## Offline evidence

Normal tests use fixed transports, Req adapters, and temporary local shell
fixtures. They make no Signal network request and do not call a real
signal-cli executable. Live tests keep the `:live` tag and remain excluded by
default.

The current result is 32 offline tests passed and one live test excluded. The
Adapter Test Kit and Source contract gate passes 12 tests. Built-in coverage is
94.07%. Quality, HTML and Markdown documentation, production compile, unused
dependency, compile-graph, dependency-tree, retired-reference, diff, and
design-review checks pass. The final xref graph has 9 files, 10 runtime edges,
no compile edges, and no cycles.

## Dependency boundary

```text
jido_chat_signal
└── jido_chat (path: ../jido_chat)
    └── jido (consolidated V3 source selected by Jido Chat)
```

The adapter lock contains no Jido Chat remote source. Package publication must
later replace the local path with the released Jido Chat V3 Hex constraint and
repeat the same gates.

## Live evidence

No live or paid provider call ran. Signal account files, daemon permissions,
remote delivery, real CLI behavior, and external service behavior are not
verified by this local unit.
