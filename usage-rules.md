# LLM Usage Rules for Jido Chat Signal

`jido_chat_signal` adapts Signal through `signal-cli`.

- Do not assume an official Signal bot API exists.
- Keep the Signal account in `Client.credentials`. Keep endpoint, executable,
  CLI config path, and receive policy in `Client.config`.
- Keep `signal-cli` account files and local daemon endpoints out of logs.
- Keep managed Sensor, Room, bridge, storage, and provider runtime ownership in
  Jido Chat core.
- Live tests must stay opt-in with `RUN_LIVE_SIGNAL_TESTS`.
