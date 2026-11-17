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
