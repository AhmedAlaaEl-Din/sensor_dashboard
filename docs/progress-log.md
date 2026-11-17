# Progress log

## Summary
_(Filled in at the end of the run.)_

## Log
- 2026-11-17 08:12: Checked the toolchain. Found Flutter 3.50.0, Dart 3.14.0, Node v26.13.1, adb, scrcpy and Java 25. tesseract and ffmpeg are missing. `adb devices` shows no phone.
- 2026-11-17 08:14: Created the git repo on branch `phase1-foundation`, plus CLAUDE.md, .claude/settings.json and .gitignore.
- 2026-11-17 08:20: Finished the broker (aedes, bound to 127.0.0.1 only), the simulator (3 devices, random walk, spikes, retained status) and the spike command. `npm test` passes 3/3 smoke tests. A manual CLI check confirmed the listener is on 127.0.0.1:18830 only.
- 2026-11-17 08:55: Finished the Flutter app scaffold and all features: dashboard, detail chart, alerts, connection bar, settings, themes. `flutter analyze` is clean.
- 2026-11-17 09:15: Tests added: unit tests (parser, stats/store, alert engine/controller, connection controller with fake_async) and widget tests (loading, empty, error, live cards, alert banner, offline, detail, dark theme). `flutter test` passes 49/49 and `flutter analyze` is clean. Fixed a gauge text overflow at large font sizes with FittedBox.
- 2026-11-17 09:25: Added a Dart e2e test (real MqttClientGateway against the Node broker and simulator). It passed against a live broker and skips itself when no broker is running. Added `npm run dev` (broker and simulator in one process).
- 2026-11-17 09:40: Docs written: README.md (features, stack, mermaid diagram, run steps, limitations, placeholders for video and screenshots), docs/phase1-explained.md and docs/demo-runbook.md.
- 2026-11-17 09:45: **Secrets scan (77 tracked files): clean.** No sensitive file names (.env, .pem, .key, keystores). No token patterns (AWS, GitHub, Slack, OpenAI/Anthropic, Google API, JWT, private keys). No password/secret/token assignments. No email addresses in file contents. No gmail/hotmail/yahoo/valeo strings outside the docs that list them as OCR search terms. demo_videos/ and evidence/ are git-ignored.
