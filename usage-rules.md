# LLM Usage Rules for Jido Chat Signal

`jido_chat_signal` adapts Signal through `signal-cli`.

- Do not assume an official Signal bot API exists.
- Keep `signal-cli` account files and local daemon endpoints out of logs.
- Live tests must stay opt-in with `RUN_LIVE_SIGNAL_TESTS`.
