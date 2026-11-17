# Needs me

Items that need the owner. Each item says what is needed and why.

## 1. Phone not connected, so no on-device run or recording (steps 6–9 skipped)
`adb devices` showed no phone at 08:12, ~09:30 and ~10:05. Nothing was installed, recorded or
screenshotted, and no OCR ran: **NOT SCANNED, needs manual review** once a video exists.
**To do:** connect the phone with USB debugging on and follow `docs/demo-runbook.md`
(about 15 minutes). The debug APK is already built at `app/build/app/outputs/flutter-apk/app-debug.apk`.
Turn on Do Not Disturb by hand before recording.

## 2. tesseract and ffmpeg are not installed
Both are needed for the OCR privacy scan of video frames (step 8). I did not install software
system-wide while you were away. **To do:** install them (for example `winget install UB-Mannheim.TesseractOCR`
and `winget install Gyan.FFmpeg`) or review the video frames by eye.

## 3. Fill in the README placeholders
The video link and the 5 screenshot cells in `README.md` are placeholders. Fill them in after you
have checked the recording and screenshots for anything personal.

## 4. Review and merge
All work is on the local branch `phase1-foundation` (not pushed, not merged), as instructed.
