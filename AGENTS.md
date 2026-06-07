# AGENTS.md - Jido Chat Signal

This package implements Signal support for `Jido.Chat` using `signal-cli`.

- Core adapter: `Jido.Chat.Signal.Adapter`
- Default transport: `Jido.Chat.Signal.Transport.JsonRpcClient`
- Live tests are tagged `:live` and require a running `signal-cli` daemon.

## Release Hygiene

- Do not modify `CHANGELOG.md`; release notes are generated from Git history during release, so keep changes focused on proper Conventional Commits.
