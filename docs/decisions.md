# Decisions

| # | Decision | Reason |
|---|----------|--------|
| 1 | The broker binds explicitly to `127.0.0.1:1883`. | Hard safety rule: local only. The phone uses `adb reverse`. |
| 2 | Both the deny list and .gitignore block `.env` files. | Prevents accidental secret reads or commits. |
| 3 | aedes 1.2.0 + mqtt 5.16.1, pinned exact. | Latest stable releases; exact pins keep installs reproducible. |
| 4 | Broker refuses any non-loopback host (throws). | Enforces the local-only rule in code, not just in docs. |
| 5 | One MQTT client per simulated device, each with a retained last-will `offline`. | Each device gets a correct retained online/offline status even if the simulator crashes. |
| 6 | Spikes: `--spike <id|all>` flag (fires 3 s after start) **and** `npm run spike -- <id>` which sends to `sensors/_control/spike` on a running simulator. | The flag satisfies the brief; the control topic lets the demo trigger a spike without restarting the stream. |
| 7 | Random spikes happen rarely (p=0.004/tick/device); `--no-random-spikes` disables them. | "Occasional spikes" as requested, and they can be disabled for a calm, predictable recording. |
| 8 | Payload timestamps are ISO 8601 UTC strings. | Unambiguous and easy to parse in Dart (`DateTime.parse`). |
| 9 | No TodoWrite tool is available in this session, so the task list lives as a checklist in progress-log.md. | The brief asked for a task list. |
