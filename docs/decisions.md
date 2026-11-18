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
| 10 | Flutter 3.50 template imports `package:material_ui/material_ui.dart`; the app uses it instead of the deprecated `flutter/material.dart`. | Matches the installed SDK and avoids deprecation warnings. |
| 11 | The threshold model is named `SensorThreshold`. | Flutter already exports a `Threshold` curve class, which caused an ambiguous import. |
| 12 | The app handles reconnect itself (backoff 1, 2, 4, 8, 10 s, then every 10 s, plus "Retry now"), with mqtt_client `autoReconnect` off. | Gives clear, testable connection states (connecting, connected, reconnecting, offline) and a countdown. |
| 13 | An `MqttGateway` interface wraps mqtt_client. | Widget and unit tests use a fake gateway with no network. |
| 14 | Default thresholds: temperature 5–35 °C, humidity 20–85 %, pressure 985–1040 hPa, battery min 20 %. | Normal simulator values stay inside; a spike (+18 °C, +25 %, −30 hPa) crosses them, so the demo shows alerts. |
| 15 | Alerts use hysteresis: they fire once on crossing and clear only when the value is back inside by a margin. | Stops alert floods when a value hovers on a limit. |
| 16 | Thresholds are edited on the Settings screen and saved with the broker settings in shared_preferences. | The brief asks to "change the threshold in settings". |
| 17 | Default host is `127.0.0.1`. | Works over USB with `adb reverse`; no LAN exposure. |
| 18 | INTERNET permission is added to the main manifest; the label is "Sensor Dashboard". | Flutter only adds it to debug/profile manifests; release builds would otherwise fail to connect. |
| 19 | Raw exceptions go to `debugPrint` only; the UI shows mapped, friendly messages. | Brief: no raw exceptions on screen. |
| 20 | `kotlin.incremental=false` in app/android/gradle.properties. | The first APK build failed: Kotlin incremental caches can't span drives (project on E:, pub cache on C:). Costs a little build speed only. |

## Phase 2

| # | Decision | Reason |
|---|----------|--------|
| 21 | API in Node with Express 5, using the built-in `node:sqlite` (no native module) and `bcryptjs` (pure JS). | Node 26 on Windows: avoids native builds (better-sqlite3, argon2), which often lack prebuilt binaries for brand-new Node versions. |
| 22 | JWT HS256, 30 min lifetime, secret generated into `api/.env` on first start (48 random bytes), never logged. | "Short-lived JWT" plus the secret-handling rule. The verifier pins `algorithms: ['HS256']` (blocks `alg: none` and confusion attacks). |
| 23 | Demo users `admin@example.com` / `admin-demo-pass` and `viewer@example.com` / `viewer-demo-pass`, documented in the README; they can be overridden with the env vars `DEMO_ADMIN_PASSWORD` / `DEMO_VIEWER_PASSWORD`. | They must be typed into the app for the demo; generating them into `.env` would force reading `.env`. They protect nothing real and exist only on 127.0.0.1. |
| 24 | Login limiter: 5 failed attempts per 5 min per IP+email (successful logins don't count). Same message and similar timing for an unknown email and a wrong password (dummy bcrypt compare). | Slows brute force without locking the whole phone (all adb-reverse traffic comes from 127.0.0.1), and avoids revealing which emails exist. |
| 25 | Thresholds live server-side (`GET/PUT /thresholds`, PUT admin-only); history delete is `DELETE /devices/:id/history` (admin-only). | "Viewer cannot change thresholds or delete history" has to be enforced by the server, not only hidden in the UI. |
| 26 | Buckets raw / 1m / 15m / 1h as averages; stats (min/avg/max) always from raw readings; raw limited to ranges ≤ 6 h; max range 31 days. | Keeps responses small for the chart while keeping stats exact. |
| 27 | CSV: ISO-8601 UTC timestamps, numbers rounded to 2 decimals, empty cell for a missing value, streamed in chunks. | Easy to open in Excel and Sheets; device ids are validated (`[A-Za-z0-9_-]`), so no CSV or formula injection. |
| 28 | Retention: delete readings older than `RETENTION_DAYS` (default 7) at start and every hour. | Matches the brief; the DB stays bounded (~1.8 M rows for 3 devices). |
