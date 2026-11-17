---
title: Signal adapter current Jido Chat V3 validation
type: implementation-plan
date: 2026-11-16
last_reviewed: 2026-11-16
artifact_contract: kata-plan/v1
artifact_readiness: complete
domain: software
execution: code
product_contract_source: approved-goal
---

# Signal Adapter Current Jido Chat V3 Validation

## Goal Capsule

- Objective: Make the Signal `release/v3` migration work with the current
  local Jido Chat V3 source and leave no retired messaging dependency,
  ownership reference, or obsolete core API.
- Means: Select the local Jido Chat path, separate the Signal account identity
  from adapter options, update the shared polling Source, correct stale
  documentation, run all offline gates, and complete an Elixir design review.
- Authority: Local Signal adapter and Jido Chat checks and local Signal adapter
  edits. No live Signal request, credential use, commit, push, release, or
  remote update.
- Stop conditions: Stop before provider I/O, a provider branch in core, a
  second process tree, or a compatibility API.
- Next executor: Elixir package engineer.

## Starting Evidence

- `release/v3` starts clean at `3fba334` and matches `origin/release/v3`.
- The branch already uses current channel, capability, invocation,
  normalization, typed Signal, Adapter Test Kit, and Sensor Source boundaries.
- It still selects an older fixed Jido Chat Git source and calls the removed
  client option helper in operations and Source polling.
- The old helper mixes the Signal account identity with endpoint, executable,
  polling, and test options.
- The README and validation report describe old binding APIs, old source
  commits, stale capability claims, and a separate Messaging runtime owner.

## Product Contract

- **R1:** Every local environment selects `path: "../jido_chat"`.
- **R2:** The Signal account stays in `Client.credentials`. Endpoint,
  executable, receive policy, and transport settings stay in `Client.config`.
  The transport receives the account as a distinct argument.
- **R3:** The adapter remains stateless. Polling uses
  `Jido.Chat.Sensor.Source`; managed provider and Room runtime stays in Jido
  Chat core.
- **R4:** Native send operations and normalized receive facts use current typed
  request, result, and event Signals. Unsupported operations stop before I/O.
- **R5:** CLI and JSON-RPC transport behavior, Source identity and cursor rules,
  stable delivery identity, provider limits, and failure facts remain offline
  and deterministic.
- **R6:** Documentation states the current V3 API, actual capability set,
  local dependency boundary, and Jido Chat runtime ownership.
- **R7:** Normal tests make no live Signal or signal-cli call. Live tests remain
  tagged and excluded.
- **R8:** Tests, contracts, coverage, quality, docs, production compile,
  unused dependencies, compile graph, dependency tree, source scan, diff
  check, and design review pass.

## Implementation Units

1. Replace the fixed Jido Chat Git dependency with the sibling local path and
   remove its stale lock entry.
2. Replace the removed client helper with explicit credentials, config, and
   transport arguments in operations and Source polling. Add direct separation
   tests.
3. Replace obsolete binding, capability, runtime-owner, release, and source
   documentation with current local V3 guidance.
4. Run all offline gates and an Elixir design review, fix supported findings,
   and repeat affected checks.

## Verification Contract

Run from `/Users/mhostetler/Source/Jido/jido_chat/jido_chat_signal`.

- The normal suite excludes `:live` and makes no provider request.
- Contract, coverage, quality, docs, production compile, unused dependency,
  xref cycle and stats, dependency tree, and diff checks pass.
- The dependency tree resolves Jido Chat from `../jido_chat`.
- Repository search finds no retired package name, removed client helper, old
  V2 constraint, old Jido Chat Git source, or obsolete source commit.
- No accepted Elixir design-review finding remains.

## Risks and Mitigations

- Risk: the account identity enters generic transport options. Mitigation:
  pass it as a distinct transport argument and test exact option lists.
- Risk: polling Source identity changes across restarts. Mitigation: hash the
  explicit account plus stable adapter config and test equality and change.
- Risk: tests execute signal-cli or a daemon call. Mitigation: preserve live
  tags and use fixed CLI and JSON-RPC test adapters in the normal suite.

## Definition of Done

- R1 through R8 have current evidence.
- Signal uses the same local Jido Chat V3 tree as completed adapters.
- No live provider check or remote change occurred.

## Execution Result

Completed locally on 2026-11-16 against `release/v3` at unchanged HEAD
`3fba334`. The adapter selects `../jido_chat`, which selects consolidated Jido
V3 at `ec96da6015b4b1e5a1642d50651235d9d52808ec`. No commit or live provider
call occurred.

The normal suite passed 32 tests and excluded one live test. The explicit
Adapter Test Kit and Source contract gate passed 12 tests. Coverage is 94.07%.
Quality, strict Credo, HTML and Markdown docs, production compilation with
warnings as errors, unused dependency, dependency tree, source scan, and diff
checks passed. The final xref graph contains 9 files, 10 runtime edges, no
compile edges, and no cycles.

## Design Review Result

The review traced the adapter contract, operation dispatch, normalization,
polling Source, CLI transport, JSON-RPC transport, documentation, and offline
test boundaries. It found and fixed these safe refinements:

1. The Signal account was mixed into generic transport options. The transport
   now receives the account as a distinct argument.
2. The transport behavior exposed an unused `list_groups` callback. The
   callback and both implementations were removed.
3. Normalization and CLI decoding used repeated list append. Both paths now
   prepend and reverse once.
4. Source identity omitted transport and CLI configuration. The key now
   includes all values that change the receive source.
5. CLI tests changed process-wide environment variables while marked async.
   Those tests now run synchronously.
6. Contract and coverage gates were implicit and important failure paths were
   not tested. The package now has an explicit contract alias, built-in
   coverage gate, and focused offline tests.
7. The package entry point and adapter formed an avoidable runtime dependency
   cycle. The entry point now delegates to the adapter, which owns its event
   definition list.

A final review of the changed state found no remaining actionable issue. The
production patch is net seven lines before generated artifacts. The increase
keeps credentials separate from provider options and makes the Source identity
complete. Most added lines are focused tests and corrected documentation.
