# Needs me

Items that need the owner. Each item says what is needed and why.

## ~~1. Phone not connected, so no on-device run or recording~~ (DONE 2026-11-17 evening)
The demo is recorded (`demo_videos/phase1-demo.mp4`), the screenshots are in `evidence/screenshots/`
(cropped copies in `clean/`), and cleanup is verified. See the on-device session in progress-log.md.

## 2. OCR privacy scan of the video: NOT SCANNED, needs manual review
tesseract and ffmpeg are not installed. Running a downloaded ffmpeg binary was blocked by the
permission system, so no frames were extracted. **To do (pick one):**
- Watch `demo_videos/phase1-demo.mp4` (72 s) yourself. It is cropped below the status bar, so it
  should show only the app; look for any notification pop-up that slid over the app.
- Or install the tools (`winget install Gyan.FFmpeg` and `winget install UB-Mannheim.TesseractOCR`)
  and run the scan in `docs/demo-runbook.md` §4.

## 3. Fill in the README placeholders
Use `evidence/screenshots/clean/*.png` (no status bar) and your video link once you've checked them.

## 4. Optional: reset the demo threshold on the phone
The app on the phone still has temperature max = 24 from the demo. Settings → Defaults → Save
puts it back to 35.

## 5. Review and merge
All work is on the local branch `phase1-foundation` (not pushed, not merged), as instructed.

---

# Phase 2

## P2-1. A separate Mosquitto broker is listening on ALL network interfaces (0.0.0.0:1883)
Found on 2026-11-18 07:45: `mosquitto.exe` (PID 19728 at that time) listens on `0.0.0.0:1883` and
`[::]:1883`. It is **not part of this project** and was not running during Phase 1. I did not stop
or change it. Why it matters:
- It is reachable from your network (Wi-Fi/LAN) on port 1883, which goes against this project's
  local-only rule. If you didn't start it on purpose, stop it or bind it to 127.0.0.1
  (`listener 1883 127.0.0.1` in mosquitto.conf), or stop the Windows service ("Mosquitto Broker").
- When our broker is stopped, the app and the API silently connect to Mosquitto instead (same port).
  `scripts/dev-up.ps1` now warns about this.
