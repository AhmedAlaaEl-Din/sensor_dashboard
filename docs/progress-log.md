# Progress log

## Merge (2026-11-20)

- Merged `phase2-history-auth` into `main` (merge commit, no conflicts; main had no extra commits) and pushed both branches at the owner's request. On merged main: API 33/33, Flutter analyze clean, 85 passed + 1 skipped (e2e skips with no broker running).

## Phase 2 video, screenshots, push (2026-11-18, 21:10)

- Uploaded `demo_videos/sensor_phase2_final.mp4` (your edit, 1:28, 720×1384) to YouTube as **unlisted**, not made for kids, title "sensor phase2 final", no description: https://youtube.com/shorts/ILTFeyNIfLA. Checks: no issues. Confirmed Unlisted in YouTube Studio → Content → Shorts.
- README: Phase 2 video link and the 7 cropped screenshots (copied from git-ignored `evidence/screenshots/` to `docs/screenshots/` so GitHub can show them).
- Pushed `phase2-history-auth` to origin at the owner's request (not merged).

## Phase 2 follow-up: seed, re-recorded demo, MQTT reconnect fix (2026-11-18, 20:30–21:00)

**Status:** done. Branch `phase2-history-auth`, **not pushed or merged**. API **33/33**, Flutter `analyze` clean, **86/86** tests.

- 20:37: **Seed script** `api/scripts/seed-history.js` (`npm run seed`, logic in `api/src/seed.js`): 7 days × 1 reading/min × 3 devices = 30,240 rows; daily cycle, drift, noise, 5 short spikes; ends at the live simulator's values. It refuses when the DB has readings the API recorded (`meta.seed_until` marker) unless `--force`, and touches neither users nor thresholds. 8 new Vitest tests. Checked against the real DB: it refused (3,594 recorded readings, exit 1).
- 20:38: **dev-up `-Seed` / `-Force`**: runs the seed before the API starts. Tested both: without `-Force` it warned and started anyway; with `-Force` it seeded 30,240 rows. README: new "Simulated history (seed)" section, dev-up options, limitation text.
- 20:39: On the phone, 24 h showed a clean day/night curve and 7 d showed seven days. The last hour looked like a staircase (the easing removed the noise), so I added per-reading noise after the easing and reseeded.
- 20:41: Take 1 of the re-recording was cut off at its 100 s limit during the outage. The run took 116 s because of adb round trips. The move of the old video to `-take1` failed (file locked by another program), so it was overwritten. That was the 2:45 take, which this request replaces anyway.
- 20:44: Take 2: every step batched into one `adb shell` call (98 s). Complete, but it ran 118 s with a ~17 s idle tail.
- 20:47: **Take 3 = final** `demo_videos/phase2-demo.mp4` (1:43, 720×1384, status bar cropped, no audio). Order: wrong password → viewer login → live dashboard → Greenhouse History 1 h → 24 h → 7 d → Export CSV → Done → Profile → sign out → admin login → temperature max 24 → heads-up + red banner → broker stopped ("Reconnecting…", "No connection") → broker restarted → "Live". Snapshots during the run confirmed each state. Only the broker was stopped (by its PID), so history kept working. Takes 1 and 2 were deleted.
- 20:50: **Bug found in logcat during the outage:** `Unhandled Exception: SocketException: Connection reset by peer`, once per reconnect attempt. Cause: with the broker down, `adb reverse` accepts and then resets the connection. mqtt_client wrote CONNECT to the dead socket (the error came from its listener, not the `connect()` future) and waited 3 attempts × 4 s. Fix (decision 45): one attempt per connect, plus a `runZonedGuarded` that turns those errors into a failed attempt or a lost connection. Regression test with a local server that accepts and drops (it failed before the fix: hung for over 8 s). Rebuilt, reinstalled, and repeated the outage on the phone at 20:54: logcat shows handled "MQTT connect failed" lines only, and it reconnected by itself. (The video was recorded with the build before this fix; it looks the same.)
- 20:56: **Clean-up.** The first Defaults → Save did **not** reach the server (still max 24): the heads-up notification covered the app bar, so my tap opened Greenhouse instead of Settings. I redid it step by step; checked with `GET /thresholds` that temperature is 5–35 again. Signed out. `dev-down -Phone`, `svc power stayon false`, `adb reverse --remove-all` (list empty), ports 1883 and 3000 free. Reseed without `--force` refused (2,922 recorded readings), so I ran `npm run seed -- --force`: the DB now holds exactly 10,080 seeded readings per device, ending 20:56, with default thresholds.
- Also fixed: runbook lines where an earlier scripted edit had dropped the backslashes (`.scriptsdev-down.ps1`).

## Phase 2 on-device session (2026-11-18, evening, phone authorized)

**Status:** steps 5–7 are now **done**. Privacy: screenshots checked by eye, video **not frame-scanned** (no tools; see needs-me P2-3). Branch still **not pushed or merged**.

- 19:46: `adb devices` shows the phone as `device`. Port 1883 was free: **Mosquitto is no longer listening** (needs-me P2-1 updated). Started `dev-up.ps1 -Phone -NoRandomSpikes`: broker 127.0.0.1:1883, API 127.0.0.1:3000, `adb reverse` for both. Installed the Phase 2 debug APK. Huawei DUB-LX1, Android 8.1, so no runtime notification permission is needed.
- 19:51: Login screen OK. Wrong password → "Wrong email or password." (real API round trip over USB). `viewer-demo-pass` → dashboard, live.
- 19:52: Greenhouse → History: 1 h (333 readings, 1-minute averages) and 24 h work. Export CSV → "CSV ready", 9 rows → Done (share sheet deliberately not opened). Profile shows Viewer with the auto sign-out time. Settings: thresholds greyed out for the viewer.
- 19:54: Signed out, signed in as admin (the first try failed because of my adb typing, not the app; see the runbook note). Temperature max 35 → 24 → Save → **heads-up notification** "Greenhouse: temperature alert" plus the in-app banner.
- 19:56: Outage: removing `adb reverse tcp:1883` did **not** drop the open MQTT connection. Stopping our services with `dev-down` showed "Reconnecting…", greyed values and "No connection". After `dev-up`, it went back to "Live" by itself.
- **Two UI issues found on the device and fixed** (decisions 39–40): (1) the 24 h chart drew a straight line across the 11 hours when the API was off, so it now breaks the line at gaps; (2) the History title was cut off ("Greenhouse …"), so it is now the device name with "History" underneath. Added 3 unit tests. `flutter analyze` is clean, `flutter test` **85/85 passed** (the e2e test ran this time because our broker was on 1883). Rebuilt and reinstalled; checked on the phone at 20:02. After the reinstall, the session was restored from secure storage and the threshold of 24 came back from the server.
- 20:03–20:06: Recorded `demo_videos/phase2-demo.mp4` (scrcpy 5.0.1, 2:45, 720×1384, status bar cropped, no audio, touches shown), driven by an adb script. Steps: viewer wrong/right password → Greenhouse history 24 h → export → profile → sign out → admin → threshold 24 → heads-up → outage → Live.
- 20:06: Clean-up: thresholds put back to defaults as admin (Settings → Defaults → Save). Screenshots `evidence/screenshots/p2-01…p2-07` cropped (status and nav bars) and reviewed by eye. `dev-down -Phone`: services stopped, port forwards removed, stay-awake off. The app is left signed in as admin on the phone.

## Phase 2 summary (2026-11-18, end of unattended run, branch `phase2-history-auth`)

**Done**
- **API** (`api/`, Node + Express 5 on **127.0.0.1:3000**): stores every MQTT reading in SQLite (`data/history.db`, git-ignored, indexed by device+time), 7-day retention job, `POST /auth/login` (bcrypt, 30-min HS256 JWT), `GET /devices`, history with raw/1m/15m/1h buckets, CSV export, shared thresholds (PUT admin-only), `DELETE` history (admin-only), login rate limit, zod validation, helmet headers, JSON-only errors. The JWT secret is generated into `api/.env` (git-ignored, never read or printed). Demo users: `admin@example.com`, `viewer@example.com`.
- **App:** login screen, Profile with role, secure token storage, auto sign-out on expiry/resume/401, History (1 h/24 h/7 d, chart, min/avg/max, pull to refresh, loading/empty/error), Export CSV → "CSV ready" → share sheet, heads-up alert notifications (tap opens the device), role-aware thresholds synced with the server, developer hints moved to the README.
- **Scripts:** `scripts/dev-up.ps1` and `scripts/dev-down.ps1` (tested: start, refused double start, stop only our PIDs; `-Phone` for adb reverse).
- **Tests:** API Vitest **25/25**; Flutter `analyze` clean, `test` **81 passed, 1 skipped** (e2e skips because the broker on 1883 isn't ours, see risks); broker smoke **3/3**. The debug APK builds.
- **Docs:** README (features, mermaid diagram simulator → broker → API + SQLite → app, API table, run steps, demo accounts, security notes, push-notification limitation, placeholders), `docs/phase2-explained.md`, Phase 2 runbook, decisions 21–38.
- **Secrets scan** (110 tracked files): **clean.** No .env, keys, AIza, private_key, JWTs or real emails. The only hits are the code that *generates* the secret and a test using `Viewer@Example.com`.

**Blocked**
- **On-device steps 5–7** (install, recording, screenshots, cleanup): the phone shows **"unauthorized"** in `adb devices` (3 checks). It needs "Allow USB debugging?" accepted on the phone.
- **Privacy scan (step 8): NOT SCANNED.** No video; tesseract and ffmpeg missing.

**Needs me:** docs/needs-me.md P2-1 (an unrelated **Mosquitto listening on 0.0.0.0:1883**, reachable from your network), P2-2 (accept the USB debugging prompt, then record with the runbook), P2-3 (privacy check after recording), P2-4 (review and merge).

**Videos / screenshots:** none for Phase 2. Phase 1 assets are unchanged in `demo_videos/` and `evidence/screenshots/` (git-ignored).

**Risks**
- The Phase 2 app has **not run on a real phone yet**. Phase 1 found a real-device-only bug (the client-id length), so expect possible device issues: notification permission, secure storage on Huawei EMUI, share sheet.
- **The Mosquitto on 0.0.0.0:1883** is outside this project: it is exposed to your network, and if our broker stops, the app and API silently connect to it.
- **compileSdk 37** and brand-new plugin versions (flutter_local_notifications 23) on a very new toolchain.
- **Background alerts** depend on Android keeping the app alive (documented; no FCM by design).
- **The broker has no auth or TLS**, and the API is HTTP. That is safe only because everything binds to loopback.

---

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
- 2026-11-18 07:52: Added `scripts/dev-up.ps1` (starts broker, simulator and API; waits for 127.0.0.1 listeners; warns about other listeners on 1883/3000; `-Phone` adds adb reverse 1883+3000; `-NoRandomSpikes`) and `scripts/dev-down.ps1` (stops only the PIDs it started; `-Phone` removes adb reverse and turns stay-awake off). Tested: start, a refused second start, stop. They run under the existing RemoteSigned policy; an `-ExecutionPolicy Bypass` invocation was blocked by the permission system, and the docs don't use it.
- 2026-11-18 08:03: Finished the Flutter Phase 2 work: login screen (server settings link), Profile (role, session end, sign out), secure token storage, auto sign-out, History screen (1 h/24 h/7 d, chart, min/avg/max, pull to refresh, loading/empty/error), CSV export with the share sheet, local alert notifications (tap opens the device), server-synced role-aware thresholds, developer hints moved out of the UI. `flutter analyze` clean; `flutter test` **81 passed, 1 skipped** (e2e). The debug APK builds after compileSdk 37 and desugaring.
- 2026-11-18 08:06: Docs: rewrote README.md (features, mermaid diagram simulator → broker → API + SQLite → app, API table, run steps with dev-up/dev-down, demo accounts, security notes protected vs demo-only, push-notification limitation, placeholders). Added docs/phase2-explained.md and a Phase 2 section in docs/demo-runbook.md.
- 2026-11-18 08:08: Secrets scan of 110 tracked files: clean (details in the summary). Final runs: API 25/25, broker 3/3, Flutter analyze clean, 81 passed + 1 skipped. The phone is still unauthorized (3rd check). Nothing of ours is left listening (only the unrelated Mosquitto on 0.0.0.0:1883).
