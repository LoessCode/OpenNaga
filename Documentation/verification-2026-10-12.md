# Issue and hardware audit, 2026-10-12

Environment: Apple Silicon MacBook Air, macOS 26.5, Xcode macOS 26.5 SDK, Naga V2 HyperSpeed receiver `1532:00b4`. The worktree started clean at `26468b5` on `main`.

## GitHub findings

| Item | Initial state | Audited change |
| --- | --- | --- |
| Issue #6, modifiers | Automated commits already on main; compilation failed on obsolete `CGEventSourceKeyState`; system-action tests had stale expectations | Modern Swift API, left/right physical modifiers, overlapping and shared holds, sequences, delayed macro cancellation and event-tap lifecycle |
| Issue #7, scroll sensitivity | Automated commit added only an unused utility, although its message claimed sliders and integration | Persisted vertical and horizontal sliders, Naga HID attribution, native event-field scaling and assigned scroll scaling |
| PR #1 | Open | Correct milliseconds at both asynchronous HID report calls |
| PR #2 | Open | Import supported assignments, preserve native controls, report unsupported functions; imported profiles are limited to explicit mouse saves to prevent incorrect software remapping |
| PR #3 | Open | Regular activation policy while settings are visible, accessory policy when closed |
| PR #4 | Open | Full sidebar-row hit area |
| PR #5 | Open | Normalize assignment reply metadata while keeping normal-layer writes, backups and verification |

The issue bot runs outside this repository. `.github` initially contained only issue templates and there were no Actions runs or build checks. Added `.github/workflows/validate.yml` for release compilation and dependency-free tests on pushes and pull requests. This does not provide hardware coverage or configure the external bot.

## Automated checks

`bash Scripts/test.sh`: **1009 checks passed**.

| Suite | Checks |
| --- | ---: |
| Input engine | 380 |
| System actions | 317 |
| Modifier delivery | 41 |
| Scroll sensitivity | 50 |
| Hardware protocol | 105 |
| Onboard profiles | 81 |
| Data folder | 24 |
| Imported profiles | 11 |

Release build and strict code-signature verification passed. Existing `onChange(of:perform:)` deprecations appear in the dependency-free compile and are retained for macOS 13 compatibility.

## Live macOS event delivery

A temporary harness used the production `ButtonMapper` without an event sink and a passive downstream CGEvent tap. F20 was used to avoid invoking common application shortcuts. Command, Control, Shift, Option, Command+Shift and all four modifiers reached the session event stream on both key edges. Each case cleared its owned modifier flags at completion. macOS adds the unrelated noncoalesced event flag; verification ignores that flag when checking modifier release.

This establishes real event delivery by the production mapper. It does not by itself establish that a physical mouse press is correctly attributed or that every third-party application handles every shortcut.

## USB receiver checks

- Read DPI `1600 × 1600`, polling `1000 Hz`, battery `93%`, mode `0`, and all 21 normal-layer descriptors in active bank 0 and stored bank 1 without warnings.
- Wrote the existing DPI and polling values and confirmed their readback.
- Saved a temporary F20 assignment on side button 1, keeping all other assignments intact, then restored the backup. All 21 active and stored descriptors matched their originals.
- Exercised the production controller's driver-mode toggle, confirmed mode 3 and a recovery journal, then used its shutdown restore path. Mode 0 returned, the journal was removed, and DPI/polling were unchanged.

An initial restore verification failed with a mismatched response; recovery retained the backup and restored the original assignment. A subsequent attempt captured repeated valid busy responses. The complete roundtrip then passed. The exact initial mismatched frame was not captured. Delayed receiver replies are a plausible explanation, rather than a confirmed diagnosis of that first frame.

Added bounded GET_REPORT-only polling for structurally valid busy replies, previous command headers and previous onboard bank/control identities. Corrupt frames and matching firmware rejection/timeout/unsupported responses still fail. Poll exhaustion throws instead of exposing busy status to the command replay path. Checks cover successful completion, corruption, firmware errors, stale assignments and exhaustion.

Later, the connected receiver returned status 4 for every telemetry request while the mouse was idle. This is reported as a mouse timeout with instructions to wake it; it is distinct from an IOKit transport timeout.

## Native interface and installation

- Inspected the live Sensitivity pane with readable hardware values and separate vertical/horizontal sliders.
- Rendered light and dark appearances at the minimum `980 × 700` content size. Settings remain in their scroll view and the sidebar/footer stay inside the window.
- Clicked the empty right edge of the Sensitivity sidebar row and verified page selection.
- Verified regular activation policy with a visible settings window, accessory policy after closing, and regular/active state after reopening.
- Installed `/Applications/OpenNaga.app`, signed with the local `NagaController Dev` identity. The user granted Accessibility and Input Monitoring. This is a local development signature, not Developer ID notarization.
- Used **Import from Mouse** in the installed app against the live receiver. It created and selected **From Mouse** with all 19 supported editable controls and persisted `onboardOnly: true`; the UI confirmed that software remapping remains paused. No unsupported assignments were reported on this mouse.
- Repeated the full hardware roundtrip after adding response polling: DPI/poll writes, temporary onboard save, all 21 active/stored restorations and the journaled driver-mode toggle/restore all passed.

## Physical input coverage

The user physically pressed side button 6 three times, rotated the wheel in both directions and tilted it in both directions. A temporary harness ran the production HID listener, event tap and mapper. Side button 6 already had the expected native 6-key assignment, so this final input test required no firmware writes.

- Three press/release pairs arrived downstream as F20 with Command+Shift on both edges and balanced modifier releases.
- All 10 vertical scroll events had exactly 2x line, pixel and application-visible `scrollingDeltaY` values.
- All 22 horizontal tilt events had exactly 3x line, pixel and application-visible `scrollingDeltaX` values.
- Physical scroll source PID was 0, with no continuous or momentum flag. Both directions were preserved.
- All original mouse assignments were unchanged at completion.

The earlier recording session expired during a long pause and its test backup was retained when the mouse fell asleep. On resume, restoration through the installed application's diagnostic command succeeded and verified all 21 assignments. The first capture helper also failed because it queried `NSEvent.scrollingDeltaY` on a flagsChanged event; this affected only the temporary measurement program. Corrected the helper, released the test modifiers and repeated the physical test successfully.

Per-button coverage, Bluetooth software remapping, power-cycle persistence, receiver unplug/replug and simultaneous physical/synthetic modifier changes are not claimed by the tests above.

Temporary harnesses, build logs and backups are in `.build/audit`; live JSON captures use `/tmp/opennaga-*`. A pending backup must be restored before more mouse writes. The legacy `NagaController` data folder was absent and was not created or modified.

## References

- Apple's installed `IOHIDDevice.h` documents the callback timeout in milliseconds, in both SetReportWithCallback and GetReportWithCallback declarations.
- [Apple CGEventField documentation](https://developer.apple.com/documentation/coregraphics/cgeventfield?language=occ).
- [OpenSnek USB protocol notes](https://github.com/gh123man/OpenSnek/blob/main/docs/protocol/USB_PROTOCOL.md) and [reply metadata discussion in PR #122](https://github.com/gh123man/OpenSnek/pull/122). Used for wire-format facts, without copying its implementation.
