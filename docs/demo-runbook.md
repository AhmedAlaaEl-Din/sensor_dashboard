# On-device demo runbook

Steps 6–9 of the Phase 1 brief, for when a phone is connected by USB. All data is simulated.
**Never open the notification shade, system settings or any account on the phone while
recording.** Before recording, turn on Do Not Disturb by hand on the phone so no real
notifications pop up.

Videos go in `demo_videos/` and screenshots in `evidence/`. Both folders are git-ignored.

## 1. Prepare

```bash
adb devices                                  # the phone must be listed as "device"
cd broker && npm install && npm run dev -- --no-random-spikes   # terminal 1, keep open
adb reverse tcp:1883 tcp:1883
adb shell svc power stayon usb               # keep the screen awake while plugged in
cd app && flutter install --debug            # or: flutter run --debug
```

Open the app and check that the bar says **Live · connected to 127.0.0.1:1883**.

## 2. Record (~60 s, calm pace)

```bash
scrcpy --no-audio --show-touches --max-size 1280 --record demo_videos/phase1-demo.mp4
```

(Older scrcpy versions use `-m 1280`. `--no-audio` keeps the recording video-only.)

Script:

| Time | Action |
|------|--------|
| 0–10 s | Dashboard: three cards updating live. |
| 10–22 s | Tap **Greenhouse**, show the chart; switch to Humidity, then back to Temperature. |
| 22–32 s | In a terminal: `npm run spike -- greenhouse`. The red banner appears and the chart spikes. |
| 32–42 s | Back, open **Settings**, change Temperature max from 35 to 30, then **Save**. |
| 42–55 s | Stop `npm run dev` (Ctrl+C). The bar turns red: "Offline · retrying in N s". Start it again; the bar returns to "Live". |
| 55–60 s | Open the alerts list (bell icon), then return to the dashboard. |

Stop the recording with Ctrl+C in the scrcpy terminal.

## 3. Screenshots

```bash
mkdir -p evidence/screenshots
adb exec-out screencap -p > evidence/screenshots/01-dashboard.png
# open a device
adb exec-out screencap -p > evidence/screenshots/02-detail.png
# after a spike
adb exec-out screencap -p > evidence/screenshots/03-alert.png
adb exec-out screencap -p > evidence/screenshots/04-alerts-list.png
adb exec-out screencap -p > evidence/screenshots/05-settings.png
# with the broker stopped
adb exec-out screencap -p > evidence/screenshots/06-offline.png
```

## 4. Privacy scan (OCR)

Needs `tesseract` and `ffmpeg`, neither of which was installed during the unattended run.

```bash
mkdir -p evidence/frames
ffmpeg -i demo_videos/phase1-demo.mp4 -vf fps=1 evidence/frames/f_%03d.png
for f in evidence/frames/*.png evidence/screenshots/*.png; do
  tesseract "$f" - 2>/dev/null | grep -i -E -n "gmail|hotmail|yahoo|valeo|wi-?fi|ssid|@|notification" \
    && echo "  ^ hit in $f"
done
```

Also check frames by eye for real names and the status bar (Wi-Fi name, notification icons).

## 5. Clean up

```bash
adb shell svc power stayon false
adb reverse --remove-all
# Ctrl+C the `npm run dev` terminal
```

---

# Phase 2 demo (login, history, export, notifications)

Simulated data only. **Do not open the notification shade, system settings or any account on the
phone.** Turn on Do Not Disturb by hand first, but **allow this app's notifications**, so only our
heads-up banner can appear. Accept the "Allow USB debugging?" prompt on the phone once
(`adb devices` must say `device`, not `unauthorized`).

## 1. Prepare

```powershell
adb devices                                     # must list the phone as "device"
.\scripts\dev-up.ps1 -Phone -NoRandomSpikes     # broker + simulator + API, adb reverse 1883 and 3000
adb shell svc power stayon usb
cd app; flutter build apk --debug; adb install -r build\app\outputs\flutter-apk\app-debug.apk
```

Let it run for a few minutes first so the History charts have data. Sign in once as admin and sign
out again, so the notification permission (Android 13+) is already granted.

**Mosquitto caveat:** if another broker listens on `0.0.0.0:1883` (see needs-me P2-1), stopping
*our* broker makes the app reconnect to that one, and the offline state won't show. Stop that
service for the recording. (Removing `adb reverse tcp:1883` is **not** enough: an MQTT connection
that is already open stays up.) The outage that worked on 2026-11-18: `.scriptsdev-down.ps1`
(no `-Phone`), wait about 10 s, then `.scriptsdev-up.ps1 -Phone -NoRandomSpikes`.

**Typing on the phone with adb:** on this Huawei keyboard, Enter in the email field does not move to
the password field. Tap each field, and hide the keyboard (Back) before tapping the next one,
because the form moves up while the keyboard is open. The scripted run used for the recording is
described in progress-log.md (2026-11-18 evening).

## 2. Record (~75 s, calm pace)

```powershell
scrcpy --no-audio --show-touches --max-size=1280 --crop=720:1384:0:56 --record=demo_videos\phase2-demo.mp4
```
(Adjust `--crop` to your screen: width:height:x:y, where y is the status-bar height.)

| Time | Action |
|------|--------|
| 0–8 s | Login screen: `viewer@example.com` with a **wrong** password → "Wrong email or password." |
| 8–14 s | Correct password `viewer-demo-pass` → dashboard, live gauges. |
| 14–24 s | Open Greenhouse → **History** → 1 h, then **24 h**. |
| 24–32 s | **Export CSV** → "CSV ready" dialog → **Done** (don't open the share sheet: it can show real contacts). |
| 32–38 s | Back → Profile (role: Viewer) → **Sign out**. |
| 38–46 s | Sign in as `admin@example.com` / `admin-demo-pass` → Profile shows Admin → back. |
| 46–58 s | Settings → Temperature max → a value **below** the current greenhouse temperature (e.g. 24) → Save, while connected. Wait for the **heads-up banner** (don't pull down the shade). |
| 58–72 s | Stop the broker (or remove the 1883 reverse, see the caveat): "Offline · retrying". Restore it: "Live" again. |

## 3. Screenshots (status bar cropped later)

```powershell
adb exec-out screencap -p > evidence\screenshots\p2-01-login-error.png
# ...repeat for p2-02-dashboard, p2-03-history-24h, p2-04-export, p2-05-profile, p2-06-notification, p2-07-offline
```
Crop the status bar (top ~56 px) and nav bar before sharing.

## 4. Clean up

```powershell
# In the app as admin: Settings → Defaults → Save (puts thresholds back on the server)
adb shell svc power stayon false
.\scripts\dev-down.ps1 -Phone        # stops our processes, adb reverse --remove-all
```

## 5. Privacy scan

Same as Phase 1 §4 (needs ffmpeg + tesseract), with these search terms:
`gmail|hotmail|yahoo|valeo|wi-?fi|ssid|@` (expect only `@example.com`). Also review every frame
with a notification banner by eye: it must be ours ("Greenhouse: temperature alert").
