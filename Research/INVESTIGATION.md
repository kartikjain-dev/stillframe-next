# CleanShot / REA investigation

## Sources and authority

- Public feature specification: https://cleanshot.com/features
- Product overview: https://cleanshot.com/
- Requested REA repository: https://github.com/morluto/rea (read-only shallow checkout at `/private/tmp/cleanshot-rea`).
- Download gate observed at https://licenses.cleanshot.com/download/cleanshotx: an email address or license key is required. No native CleanShot app was found in `/Applications`. The user selected continuing from public documentation.

REA is an analysis toolkit, not a capture engine or a clone generator. The new application uses Apple frameworks directly; REA is a research tool only.

## Executed analysis

The public feature page and its first-party Nuxt entry script, `https://cleanshot.com/_nuxt/0UUDQsxc.js`, were downloaded as inert text. No site code was executed. Third-party payment and analytics scripts were not downloaded.

Published CLI **rea-agents 6.7.0** was installed in `/private/tmp/frame-rea-tools`. The reviewed Git checkout reported 6.8.0, so its docs can differ from the installed CLI. Global agent configuration was not changed. A compatible Node package was downloaded but not used; execution succeeded with the host Node 22.23.1. The reviewed repository advertises a newer minimum patch; do not treat this run as general Node compatibility certification.

Command executed (before renaming the local project from Frame to Stillframe):

```sh
node /private/tmp/frame-rea-tools/node_modules/rea-agents/scripts/rea.mjs \
  analyze-javascript-application \
  /Users/kartikjain/Desktop/code/apple/Frame/Research/site --json
```

The initial sandboxed run failed because REA's macOS process helper could not compile into the user compiler cache. The approved run with normal compiler-cache access completed with exit code 0. This was static, read-only target analysis.

- Evidence ID: `ev_846d732d45cc0c01d310e730e8fbb857e6963be6eb626d693e04e863545bd335`
- Root artifact SHA-256: `4384485318bdb3972ed33a29003ee842d0a06cc14e7dfd3fef13a6a0b94cdb28`
- Two relevant files; 246,961 text bytes; one parsed JavaScript file; zero parse failures; 35,922 AST nodes visited; 749 findings.
- `rea-summary.json` is a small projection of the analyzer's returned statistics/limitations produced by Python, not an additional REA operation.
- Complete evidence: `rea-website-analysis.json` (about 38 MB, kept locally and ignored by Git). Downloaded targets: `site/` (also ignored). The evidence retains the original pre-rename paths.
- A separate attempt to use `inspect-analysis-view` with the source checkout's `evidence-file` syntax was rejected by installed 6.7.0; it was not used as evidence.

## What this establishes

REA parsed the selected public website artifacts and emitted an authenticated static analysis graph. Coverage is incomplete: dynamic relationships, other Nuxt chunks, third-party scripts and inline script bodies are not covered. These are marketing-site observations, not evidence of how the native capture app is implemented.

The public feature descriptions establish user-visible concepts: multiple capture modes, an immediate action overlay, annotations, cropping, backgrounds, floating images, OCR, capture history and MP4 recording. Stillframe implements those concepts independently with native Apple APIs.

## Implementation mapping

| Publicly described behavior | Stillframe implementation |
| --- | --- |
| Area/window/fullscreen capture and timer | Apple's `screencapture` selection UI and timed process invocation |
| Immediate capture actions | Floating native panel; copy, export, edit, pin and image drag |
| Annotation tools | AppKit renderer shared by preview, flattened export, clipboard and OCR |
| Text recognition | Vision `VNRecognizeTextRequest`, on-device |
| Capture history | Local PNG/MP4 files plus Codable JSON metadata and editable marks |
| Floating screenshots | Resizable floating NSPanel |
| MP4 recording with system audio | ScreenCaptureKit SCStream + SCRecordingOutput, H.264 |

No CleanShot assets, source code, account access, cloud service, or license behavior were reused. Missing feature areas are listed in the project README. This investigation does not claim binary reverse engineering or full behavior/visual parity.
