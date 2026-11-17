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
