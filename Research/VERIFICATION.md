# Stillframe 0.3.0 — clipboard, extension and shortcuts (2026-11-06)

- Release build succeeds; **19 tests pass** with native clipboard/media-service access.
- Every completed area, fullscreen, window and scrolling capture now publishes a self-contained PNG/TIFF clipboard item before showing capture actions. A named-pasteboard integration test verifies all four completion paths, including migration from an older `copyAfterCapture: false` setting. Pasteboard tests do not overwrite the user's general clipboard.
- New area/fullscreen captures retain their Quartz capture rectangle. Extend reuses it; older/window/imported/cropped captures can select the original region again. The seed preserves existing redactions/annotations as pixels and omits decorative padding. Tests verify region persistence, crop/undo behavior and redacted seed pixels.
- Scrolling can be controlled from the target app with the configurable Add Frame and Finish actions. Finish copies the combined screenshot. Region selection now also accepts Return for the whole display.
- Shortcut support includes Option combinations, punctuation, navigation keys and standalone F1–F20. Settings suspend global capture shortcuts while recording a new binding. Native UI verification recorded Control–Option–Command–8 successfully; recommended bindings were restored/applied afterward. Migration preserves existing choices and disables a new default when it would collide.
- Native menu equivalents use the correct AppKit function/navigation-key characters; automated checks caught and fixed an arrow-key mapping issue.
- The final rebuilt app again reported missing Screen Recording permission during a live fullscreen attempt. No new 0.3.0 screenshot/scrolling-session success is claimed. Refresh access for the final build and launch it normally; see the earlier successful recheck and ad-hoc signing caveat below. There is no valid code-signing identity available on this machine, so the local build remains ad-hoc signed.

Recommended defaults: Control–Command–Shift–4 (area), –3 (screen), –5 (record), –6 (scroll/add), and Control–Command–Shift–Return (finish/copy).

---

# Current-build recheck — 2026-11-06

Screen permission is now working for the existing 0.2.0 build; no source changes or rebuild were needed during this recheck.

- Fullscreen capture succeeded and added a new **3024 × 1964** screenshot to the library.
- Screen recording started, stopped and saved successfully. The video workspace loaded the new MP4 and reported a **5.49-second** duration; the library now contains five captures.
- Scrolling capture passed its permission check and opened the full-screen region picker. Escape cancelled it successfully and returned to the editor.
- The automation tool could not drag in the borderless region picker (`noWindowsAvailable`), despite its window and screenshot being visible. Live region sampling and multi-frame stitching remain unverified end-to-end; this recheck does not claim they passed. The stitch-engine tests listed below remain the available evidence for joining frames.

This supersedes the earlier permission-blocked status for this build. No recording or scrolling session was left running.

---

# Stillframe 0.2.0 — expanded coverage

## Verified

- Release build succeeded; bundle reports **0.2.0**. Code signature validates and Info.plist passes validation.
- **15 tests passed, zero failures**, with normal macOS media-service access. A sandboxed media test initially failed because the H.264 encoder service was unavailable; it passed outside that restriction.
- Real integration test: generates a three-second H.264 source, exports a one-second MP4 trim, decodes a ten-frame animated GIF, replaces an existing destination, rejects invalid ranges and source overwrite, and checks cancellation/source preservation and temporary-file cleanup.
- Scrolling engine: three overlapping image regions join to the expected 160 × 720 image, with pixel checks across both seams. Duplicate/incompatible frames are rejected; explicit overlap is also exercised.
- Settings: shortcut duplicate/modifier/key validation; settings persistence; corrupt settings do not hide history; old capture metadata loads; background settings/assets persist per capture and support Undo/Redo.
- Native UI: set a recording's start/end to 1s/3s; exported `stillframe-ui-clip.gif`; app reported successful save. File is a valid 720 × 467 GIF in `/private/tmp`.
- Native UI: inspected Shortcuts/Capture/Background tabs and successfully applied unchanged defaults. The per-image Sunset preset visibly rendered and was left open in the editor.
- Native UI: denied scrolling access now produces a useful permission alert rather than silently returning.

## Remaining live checks

- The rebuilt app's CoreGraphics preflight continued reporting no permission, even while System Settings showed its toggle enabled. Refreshing the toggle, removing/re-adding the exact bundle and Quit & Reopen did not resolve this during automation. The cause is not established; an ad-hoc signature change or the automated launch context may be involved. Do not treat old 0.1.0 live-capture results below as a 0.2.0 capture verification.
- A controlled TextEdit scrolling test could not proceed: the computer-use app launch timed out. Consequently the region-picker → live frame sampling → stitched library item flow remains unverified end-to-end. Its image-stitching algorithm is covered by the passing tests above.
- Confirm current-build Screen Recording access after a normal Finder launch, then run Scroll: select content, scroll down with overlap, Add Frame, Finish. If access still fails, inspect the app's TCC/signing identity rather than repeatedly toggling the same permission.
- Configurable global shortcuts are validated/tested in code and re-registration succeeded when applying defaults, but newly assigned combinations were not exercised across apps. Recording FPS/resolution/audio options and custom-image selection were not separately live-tested.

Scrolling is guided, vertical and downward: the user scrolls and samples frames; automatic scrolling and horizontal stitching are not implemented. GIFs are silent, up to 30 seconds, with bounded frame rate/size. Cloud, webcam/microphone capture and Studio Mode remain outside this update.

---

# Verification — 2026-11-05

Verified locally on macOS 15.7.7 (Apple silicon):

- Release build via `./build.sh`: succeeded; local ad-hoc signed `Stillframe.app` assembled.
- `codesign --verify --deep --strict --verbose=2 Stillframe.app`: valid on disk; satisfies its designated requirement.
- `plutil -lint Stillframe.app/Contents/Info.plist`: OK.
- `./test.sh` with installed Xcode: **7 tests, 0 failures**. Covers annotation rendering/serialization, solid redaction pixels, crop bounds and vertical orientation, backdrop dimensions, persistent history/edits, undo/redo including crop, search/filter, deletion and corrupt-manifest reporting.
- Native UI: app launched; image imported through NSOpenPanel; drag-to-redact visibly rendered an opaque black rectangle; Undo/Redo and backdrop toggle worked; Copy Text completed successfully; PNG exported through NSSavePanel.
- Export `/private/tmp/stillframe-export.png`: valid 1000 × 640 RGBA PNG.
- After the user's approval, System Settings visibly showed Stillframe's Screen & System Audio Recording switch on.
- Fullscreen capture: successfully added a 3024 × 1964 capture to the library.
- Screen recording: successfully started and stopped; an MP4 appeared in history; built-in AVPlayer reported a five-second duration and entered playback when Play was clicked.

Not live-tested: interactive area/window selection, timed capture, global shortcuts, multi-display behavior, system-audio recording, drag-to-other-app, pin panels and JPEG export. These use native APIs but are not represented as session-verified behavior.

This is core local workflow coverage, not full CleanShot parity. Scrolling capture, cloud/collaboration, microphone/webcam, GIF output and Studio Mode/video editing are not implemented. See README for scope and original-file retention during redaction.

REA's public-site static analysis completed successfully; details and evidence identifiers are in `INVESTIGATION.md`. No native CleanShot binary was available, and the user selected public documentation as the implementation reference.
