# Progress log

## Summary (2026-11-17, end of unattended run)

**Done**
- Broker (aedes, **127.0.0.1:1883 only**; refuses any other host), simulator (3 devices, smooth random walk, rare random spikes, retained online/offline with last will), spike command (`--spike <id>` flag and `npm run spike -- <id>`), `npm run dev` (both in one process).
- Flutter app (`com.ahmed.sensor_dashboard`, Material 3, provider, feature folders): live dashboard with gauges, detail chart (fl_chart, last 60 points) with min/avg/max and threshold lines, alerts (banner, badge, history, hysteresis), connection bar with auto-reconnect and backoff and an offline state, settings (host/port/prefix/thresholds/theme in shared_preferences), loading/empty/error states, light and dark themes, friendly errors only.
- Tests: `flutter analyze` clean; `flutter test` **52 passed, 1 skipped** (the e2e test skips when no broker is running; it passed earlier against the live broker); `npm test` **3/3** (broker + simulator smoke test, including the loopback-only check).
- Debug APK builds: `app/build/app/outputs/flutter-apk/app-debug.apk`.
- Docs: README.md (with mermaid diagram and placeholders), docs/phase1-explained.md, docs/demo-runbook.md, docs/decisions.md (20 decisions), CLAUDE.md, .claude/settings.json.
- Secrets scan of 77 tracked files: **clean**.
- Small commits on `phase1-foundation`. Nothing pushed or merged.

**Blocked**
- Steps 6–9 (install on phone, scrcpy recording, screenshots, OCR, cleanup): **no phone connected** in any check.
- OCR: **NOT SCANNED, needs manual review** (no video exists; tesseract and ffmpeg not installed).

**Needs me:** see docs/needs-me.md. Connect the phone and follow docs/demo-runbook.md, install tesseract and ffmpeg (or review by eye), fill in the README placeholders, then review and merge the branch.

**Videos / evidence:** none yet. They will go in `demo_videos/` and `evidence/` (both git-ignored).

**Risks**
- The app has not been run on a real phone yet; it is verified only by tests and the APK build.
- The broker has no TLS or auth. That is safe only because it is loopback-only; never expose it.
- Toolchain is very new (Flutter 3.50, Material from `material_ui`, Gradle 9.5, JDK 25). The build needed `kotlin.incremental=false` because the project is on E: and the pub cache is on C:.
- Alert history and chart data are in memory only (lost when the app restarts).

## Log
- 2026-11-17 08:12: Checked the toolchain. Found Flutter 3.50.0, Dart 3.14.0, Node v26.13.1, adb, scrcpy and Java 25. tesseract and ffmpeg are missing. `adb devices` shows no phone.
- 2026-11-17 08:14: Created the git repo on branch `phase1-foundation`, plus CLAUDE.md, .claude/settings.json and .gitignore.
- 2026-11-17 08:20: Finished the broker (aedes, bound to 127.0.0.1 only), the simulator (3 devices, random walk, spikes, retained status) and the spike command. `npm test` passes 3/3 smoke tests. A manual CLI check confirmed the listener is on 127.0.0.1:18830 only.
- 2026-11-17 08:55: Finished the Flutter app scaffold and all features: dashboard, detail chart, alerts, connection bar, settings, themes. `flutter analyze` is clean.
- 2026-11-17 09:15: Tests added: unit tests (parser, stats/store, alert engine/controller, connection controller with fake_async) and widget tests (loading, empty, error, live cards, alert banner, offline, detail, dark theme). `flutter test` passes 49/49 and `flutter analyze` is clean. Fixed a gauge text overflow at large font sizes with FittedBox.
- 2026-11-17 09:25: Added a Dart e2e test (real MqttClientGateway against the Node broker and simulator). It passed against a live broker and skips itself when no broker is running. Added `npm run dev` (broker and simulator in one process).
- 2026-11-17 09:40: Docs written: README.md (features, stack, mermaid diagram, run steps, limitations, placeholders for video and screenshots), docs/phase1-explained.md and docs/demo-runbook.md.
- 2026-11-17 09:45: **Secrets scan (77 tracked files): clean.** No sensitive file names (.env, .pem, .key, keystores). No token patterns (AWS, GitHub, Slack, OpenAI/Anthropic, Google API, JWT, private keys). No password/secret/token assignments. No email addresses in file contents. No gmail/hotmail/yahoo/valeo strings outside the docs that list them as OCR search terms. demo_videos/ and evidence/ are git-ignored.
- 2026-11-17 10:05: Debug APK build attempt 1 failed (Kotlin incremental cache error across the E: and C: drives). Attempt 2, with kotlin.incremental=false, succeeded: app/build/app/outputs/flutter-apk/app-debug.apk. The Android SDK Platform 35 and CMake were auto-installed by Gradle.
- 2026-11-17 10:15: Final checks: analyze clean, 52 Flutter tests passed + 1 skipped, 3/3 Node tests, nothing listening on 1883. Wrote needs-me.md and the summary.
