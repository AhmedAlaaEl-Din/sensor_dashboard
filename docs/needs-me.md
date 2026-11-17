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
