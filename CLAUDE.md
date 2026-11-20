# Sensor Dashboard: project rules

Flutter Android app showing live **simulated** sensor data from a local MQTT broker.

## Layout
- `app/`: Flutter app (package `com.ahmed.sensor_dashboard`, Material 3, provider, feature-based folders).
- `broker/`: Node.js aedes MQTT broker (127.0.0.1:1883) and the telemetry simulator.
- `docs/`: decisions.md, needs-me.md, progress-log.md, phase1-explained.md.

## Hard safety rules
- **Local only.** The broker binds to `127.0.0.1`. Never bind to `0.0.0.0`, never expose a port to the
  internet, and never ask the owner to port-forward. The phone reaches the broker with
  `adb reverse tcp:1883 tcp:1883`, not over the network.
- No real credentials, no cloud services, no accounts. Use only generated simulated data.
- Do not read files outside this project folder. Do not read `.env` files.
- Recordings and screenshots show simulated sensor data only. Never open the notification shade,
  system settings, or real accounts on the phone.
- Videos and evidence go in the git-ignored folders `demo_videos/` and `evidence/`.

## Git
- Phase 1 is on `main` (pushed to GitHub on 2026-11-18 at the owner's request). Phase 2 (`phase2-history-auth`) was merged into `main` and pushed on 2026-11-20 at the owner's request. Make small commits. **Push or merge only when the owner asks.**

## Working while the owner is away
- Do not stop to ask. Pick the safest reasonable option and log it in `docs/decisions.md`.
- Put anything that needs the owner in `docs/needs-me.md`.
- Keep `docs/progress-log.md` up to date (timestamp + what finished).
- If the same problem fails 3 times, log it in needs-me.md and move on.

## Commands
- Broker: `cd broker && npm install && npm run broker`
- Simulator: `npm run simulate` (spike: `npm run simulate -- --spike greenhouse`)
- App: `cd app && flutter pub get && flutter analyze && flutter test`
