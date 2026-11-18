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

**Update (evening session, phone connected):** steps 6–9 are DONE. Video: `demo_videos/phase1-demo.mp4` (72 s). Screenshots: `evidence/screenshots/` (+ `clean/` without the status bar). Found and fixed on the device: the broker rejected the client id (MQTT 3.1 23-char limit), plus 2 layout issues. Cleanup is verified. OCR: **NOT SCANNED, needs manual review** (no ffmpeg/tesseract; running a downloaded binary was blocked). Details are in "On-device session" below.

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
- 2026-11-17 20:50: **Bug found on the device:** the broker rejected the app (identifierRejected). mqtt_client defaults to MQTT 3.1, which caps client ids at 23 chars, and the generated id `sensor-dashboard-<hex>` was up to 25. Fix: MQTT 3.1.1 (`setProtocolV311`) and a 14-char id `sdash-<8 hex>`. Also fixed the error message, which said 'can't reach' when the broker had actually refused. Added 2 regression tests: 55 passed, analyze clean, APK rebuilt.

## On-device session (2026-11-17, evening, phone connected)

- 20:40: Phone found: Huawei DUB-LX1, Android 8.1, 720x1520, unlocked. Started the broker and simulator (`npm run dev -- --no-random-spikes`, listening on 127.0.0.1:1883 only). Ran `adb reverse tcp:1883 tcp:1883` and `adb shell svc power stayon usb`, then installed the debug APK. The first install took about 5 min; later ones took about 27 s.
- 20:44: The first launch showed the offline error screen. The friendly message and Retry/Check-settings buttons worked, but the app could not connect.
- 20:46: **Bug found and fixed:** the broker rejected the connection with `identifierRejected`. The client id `sensor-dashboard-<hex>` (up to 25 chars) breaks the MQTT 3.1 limit of 23. The app now uses MQTT 3.1.1 and the 14-char id `sdash-<8 hex>`, and a broker rejection reads as "refused" instead of "can't reach". Added 2 regression tests. Commit `Fix broker rejecting the app…`.
- 20:47: The app connected: Live, 3 devices, gauges updating.
- 20:48: **Layout fixes found on the device:** the sensor selector clipped "Battery" (now wrapping chips), and the chart's y-axis edge labels overlapped (edge labels hidden). Rebuilt and reinstalled. 55/55 tests passed and analyze was clean.
- 20:51–20:53: **Recorded the demo** with `tools/record-demo.js` (scrcpy 5.0.1: `--no-audio --show-touches --max-size=1280 --crop=720:1384:0:56 --time-limit=72`). The crop removes the status bar, so no notification icons are in the video. The script drove the app with `adb shell input` taps only; the notification shade, system settings and accounts were never opened.
  - Sequence: dashboard live → open Greenhouse → Humidity/Temperature chart → `spike greenhouse` → 3 alerts (temperature 42.3 > 35, humidity 95.4 > 85, pressure 981.8 < 985), resolved after about 6 s → back → Settings → temperature max 35 → 24 → Save ("Settings saved", new alert 25.9 > 24) → **broker stopped**: cards greyed out, "No connection", status bar "Reconnecting…/Offline" → broker restarted at +7 s and the app reconnected → alerts list → dashboard.
  - Timing note: each `adb input keyevent` takes about 1 s on this phone, so the threshold edit ran about 6 s late. The broker stopped about 0.4 s after Save, and the "Settings saved" snackbar is still visible on the offline screen. Everything still appears in order.
  - Output: `demo_videos/phase1-demo.mp4` (5.6 MB, 72 s).
- Screenshots (adb screencap): `evidence/screenshots/01-dashboard.png`, `02-detail.png`, `03-alert.png`, `04-alerts-list.png`, `05-settings.png` (retaken; the first capture fired before the page opened), `06-offline.png`. Copies with the status and nav bars cropped off are in `evidence/screenshots/clean/` (local crop with System.Drawing). I reviewed all 6 by eye: only app UI and simulated data. The raw (uncropped) ones show status-bar icons (signal, Wi-Fi, USB, a mail-app icon, battery, clock) but **no notification text, no Wi-Fi name, no names or emails**.
- **OCR privacy scan: NOT SCANNED, needs manual review.** tesseract and ffmpeg are not installed. I installed `ffmpeg-static` and `tesseract.js` into a scratchpad folder, but running the downloaded ffmpeg binary was blocked by the permission system, so I did not extract frames. The video has not been scanned automatically. Mitigations: the video is cropped below the status bar, and the content is the app only.
- Declined by the permission system and not attempted further: (1) Android demo mode (`settings put global sysui_demo_allowed`) to hide status-bar icons. I cropped instead, leaving the phone settings untouched. (2) `taskkill /IM node.exe` earlier in Phase 1 (too broad). I stopped only my own processes.
- 20:54: **Cleanup done and verified:** `svc power stayon false`; `adb reverse --remove-all` (list now empty); `show_touches=0` (scrcpy restored it); the broker and simulator are stopped (nothing listening on 1883); no scrcpy left running.
- Leftover on the phone: the app is installed with temperature max = 24 saved from the demo. Settings → Defaults → Save resets it.
- 2026-11-18: Added GitHub remote `origin` (https://github.com/AhmedAlaaEl-Din/sensor_dashboard.git; remote is empty, nothing pushed). Uploaded `demo_videos/sensor_dashboard_demo_final.mp4` (owner's final cut, 1:07) to the owner's YouTube channel at the owner's request: unlisted, not made for kids, description 'This video shows a demo for sensor dashboard'. Link: https://youtube.com/shorts/mwZjokxNZyg. Added to README.
- 2026-11-18: Owner asked to push. There was only one branch, so it was renamed `phase1-foundation` → `main` and pushed with `git push -u origin main`. The secrets re-scan before the push was clean. No PR/merge was needed. CLAUDE.md git rule updated.

---

# Phase 2: login, history, export and alerts

## Log
- 2026-11-18 07:38: Created branch `phase2-history-auth` from `main`. `adb devices` shows the phone as **unauthorized**: the USB-debugging prompt on the phone has not been accepted. I'll re-check later. tesseract and ffmpeg are still missing.
- 2026-11-18 07:45: Finished the API (`api/`): MQTT ingest into SQLite (`data/history.db`, indexed by device+time), login/JWT, devices, history with buckets, CSV export, thresholds, admin-only delete, retention job, helmet, rate limit, zod validation, JSON-only errors. Vitest: **25/25 passed**. A live check against the real broker worked: wrong password gives 401, viewer login works, 3 devices listed, history and CSV OK. The API listens on 127.0.0.1:3000 only. `api/.env` was generated (not read) and is git-ignored. **Found** an unrelated Mosquitto on 0.0.0.0:1883 (needs-me P2-1).
- 2026-11-18 08:00: Added `scripts/dev-up.ps1` (starts broker, simulator and API; waits for 127.0.0.1 listeners; warns about other listeners on 1883/3000; `-Phone` adds adb reverse 1883+3000; `-NoRandomSpikes`) and `scripts/dev-down.ps1` (stops only the PIDs it started; `-Phone` removes adb reverse and turns stay-awake off). Tested: start, a refused second start, stop. They run under the existing RemoteSigned policy; an `-ExecutionPolicy Bypass` invocation was blocked by the permission system, and the docs don't use it.
- 2026-11-18 09:05: Finished the Flutter Phase 2 work: login screen (server settings link), Profile (role, session end, sign out), secure token storage, auto sign-out, History screen (1 h/24 h/7 d, chart, min/avg/max, pull to refresh, loading/empty/error), CSV export with the share sheet, local alert notifications (tap opens the device), server-synced role-aware thresholds, developer hints moved out of the UI. `flutter analyze` clean; `flutter test` **81 passed, 1 skipped** (e2e). The debug APK builds after compileSdk 37 and desugaring.
