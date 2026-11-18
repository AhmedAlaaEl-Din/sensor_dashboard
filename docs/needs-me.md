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

**Update 2026-11-18 19:46:** nothing was listening on 1883 any more, so Mosquitto has stopped
(by you or on its own). If it is an automatic Windows service, it can come back after a reboot,
so it is still worth checking the service's startup type.

## ~~P2-2. Phone shows "unauthorized", so steps 5–7 (install, recording, screenshots, cleanup) were skipped~~ (DONE 2026-11-18 evening)
Done after you accepted the prompt: installed, walked through, recorded `demo_videos/phase2-demo.mp4`,
7 screenshots in `evidence/screenshots/p2-*.png`, cleaned up. See progress-log.md. Original note:

`adb devices` listed `58K6R19924012174  unauthorized` at 07:38, 08:03 and 08:08. The phone is
waiting for **"Allow USB debugging?"** to be accepted on its screen, which only you can do. Nothing
was installed or recorded, and no phone settings were changed. **To do:** unlock the phone, accept
the prompt (tick "Always allow from this computer"), then follow `docs/demo-runbook.md` → "Phase 2
demo". The debug APK is built: `app/build/app/outputs/flutter-apk/app-debug.apk`.
Note: the phone still has the Phase 1 app with temperature max = 24. After installing Phase 2 and
signing in, thresholds come from the server (defaults 5–35 °C), so that resets itself.

## P2-3. Privacy scan: screenshots CHECKED BY EYE, video NOT SCANNED
The 7 Phase 2 screenshots were reviewed by eye: status and nav bars cropped, only demo data and
`@example.com`, the only notification is ours. The video (`demo_videos/phase2-demo.mp4`, 2:45,
status bar cropped at record time) could not be frame-checked: no ffmpeg, tesseract or OpenCV.
It was recorded with the status bar cropped and no other app opened, but a heads-up from another
app could still have appeared during the 2:45. **Watch it once before publishing.** Full check:
1. Install the tools: `winget install Gyan.FFmpeg` and `winget install UB-Mannheim.TesseractOCR`.
2. Run the scan in `docs/demo-runbook.md` (Phase 1 §4 commands, Phase 2 §5 search terms).
3. Watch every frame with a notification banner: it must be ours, never another app's.
4. Check that the status bar is cropped off in the video and screenshots.

## P2-4. Review and merge
All Phase 2 work is on the local branch `phase2-history-auth` (not pushed, not merged), as instructed.
