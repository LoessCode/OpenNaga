# AGENTS.md

## Purpose

OpenNaga: macOS menu bar app (Swift, AppKit + SwiftUI, no Xcode project) that remaps the buttons of the Razer Naga V2 HyperSpeed and controls DPI / polling rate over the USB receiver `1532:00b4`. Standalone project that started as a fork of DParent10/NagaController (credited in README and LICENSE); remote `origin` is `Zer0codestuff/OpenNaga`. Not affiliated with Razer.

Naming: the shipped app is `OpenNaga.app` (executable `OpenNaga`, display name OpenNaga). The SwiftPM package/product/target, `Sources/NagaController`, the bundle id `com.zer0codestuff.NagaController` and the "NagaController Dev" signing identity intentionally keep the old name so TCC grants carry over. Data lives in `~/Library/Application Support/OpenNaga` since 2.4.0; the older `NagaController` folder belongs to the upstream app and is only read once for import.

## Architecture

- `Sources/NagaController/main.swift`: CLI switches (`--diagnose`, `--diagnose-file <path>`, `--verify-hardware`, `--inspect-onboard`, `--save-onboard-profile`, `--restore-onboard-profile`, `--snapshot <png>`), otherwise starts `AppDelegate`.
- `AppDelegate`: starts `HIDListener`, `RazerDeviceController.refresh()`, the event tap (only when Accessibility and Input Monitoring are granted), a 2 s permission poll, menu bar item and popover; defers quit until `restoreOriginalMode` completes.
- `ButtonMapping/`: `ActionType` (system, legacy audio, mouse, disabled, keySequence, application, systemCommand, textSnippet, macro, profileSwitch), `ButtonMapper` (press/hold/release semantics, synthetic marker `eventSourceUserData`), `KeyboardLayoutShortcut` (browser back/forward per layout). `SystemAction` groups native system controls; `MacSystemShortcut` reads configured macOS shortcuts without changing preferences.
- `EventTap/EventTapManager`: CGEvent tap; consumes an event only if `HIDListener.consume` matches a HID edge within 25 ms. Logical indices: 1..12 side grid, 13 DPI up, 14 DPI down, 15 wheel left, 16 wheel right, 17 middle, 18 left, 19 right.
- `HID/HIDListener` + `HID/InputModel`: IOHIDManager on a dedicated thread, pure decoders (`NagaInput`, `InputEdgeMatcher`, `DriverButtonState`). Enumeration includes vendor `1532` and exact BLE identity `068e:00b5`; callbacks additionally validate Naga identity.
- `Hardware/`: `RazerProtocol` (90-byte report codec, CRC, transaction IDs), `MacRazerUSBTransport` (IOHID feature reports on the mouse collection with 90-byte feature size), `RazerDeviceController` (`@MainActor` facade, serial worker queue, driver-mode recovery journal `driver-mode-recovery.json` in the data folder), a nonblocking `hardware.lock` so GUI and CLI sessions never interleave. Onboard memory: `RazerOnboardBindings` (21-control inventory and 10-byte descriptors, class 2 commands 0x84/0x8c), `OnboardProfilePlan` (actions to USB HID function blocks; unsupported actions block the whole save), `OnboardProfileStore` (writes only changed bindings to stored bank 1 via 0x0c, verifies bank 1 and active bank 0, keeps the original assignments in `onboard-profile.json`, rolls back on failure; the backup follows the receiver model `1532:00b4`, not the USB port).
- `UI/`: `MappingViewController` (NSHostingController with `NagaWorkspace`), `ActionInspector`, `SettingsPanes` (Sensitivity, Status, ProfileManager), `OnboardProfilePane` (Mouse Memory sheet), `MainViewController` (popover), `MappingWindowController`.
- `Utils/ConfigManager`: profiles JSON, auto-save, `didChangeNotification`, `lastError`, persisted scroll multipliers. Mouse imports carry optional `Profile.onboardOnly`; their editor mappings remain intact while runtime mappings are empty, so custom firmware events cannot be remapped as the wrong physical controls.
- `Utils/ScrollSensitivity`: per-axis 0.1x...5x settings, fractional accumulation, discrete Naga HID scroll correlation and line/fixed-point/pixel/raw/accelerated event scaling. Shift-wheel uses horizontal sensitivity. Continuous, momentum and other-process events bypass scaling.
- `Utils/DataFolder`: the only place that names the data folder. `importLegacyFilesIfNeeded()` runs first in `main.swift`: it copies `profiles.json`, `onboard-profile.json`, `driver-mode-recovery.json` and `onboard-profile.*.bak.json` from the `NagaController` folder when they are missing in `OpenNaga`, then writes `.legacy-import-done`. It never overwrites, writes to or deletes the older folder; a failed copy leaves the marker out so the next launch retries.

## Build, run, test

```bash
swift build                      # debug
bash Scripts/make_dev_certificate.sh   # once: self-signed "NagaController Dev" identity, keeps TCC grants across rebuilds
bash Scripts/build_app.sh        # release bundle ./OpenNaga.app, signed with the dev identity if present, else ad-hoc
bash Scripts/test.sh             # 1020 dependency-free checks, including async modifier/macro checks
bash Scripts/make_dmg.sh         # ad-hoc signed release DMG (OpenNaga-v<version>.dmg, git-ignored)
gh release create vX.Y.Z OpenNaga-vX.Y.Z.dmg --title "OpenNaga X.Y.Z" --notes-file <file>   # publish
open OpenNaga.app --args --diagnose-file /tmp/naga.json   # read-only hardware probe
open -n OpenNaga.app --args --inspect-onboard --diagnose-file /tmp/o.json   # read-only onboard dump (quit the GUI first)
./OpenNaga.app/Contents/MacOS/OpenNaga --snapshot /tmp/ui.png  # UI render without hardware
```

`Package.swift` also declares a `TapTester` executable and an XCTest target (`Tests/NagaControllerTests`) that cannot run without Xcode.

## Current status (2026-10-12)

- Single branch: everything lives on `main`. Feature branches and extra worktrees were removed after 2.3.0; do not create long-lived branches.
- Version 2.3.0, build 7: onboard memory (Save to Mouse / Restore Previous Assignments) ported from the Italian 2.1.1-based work onto 2.2.0, translated, renamed to OpenNaga. Published as GitHub release v2.3.0 with `OpenNaga-v2.3.0.dmg` (Apple Silicon, ad-hoc signed, not notarized).
- Version 2.4.0, build 8: own data folder with one-time import, released as v2.4.0. Verified with the release bundle in an isolated home (`CFFIXED_USER_HOME`) holding copies of the user's real `profiles.json` and mouse backup: files imported byte for byte, the Test profile and "Mouse memory: Test" shown, no re-import on the second launch, older folder unchanged. Not checked on hardware, since only file locations changed.
- Version 2.5.0, build 9: scroll sensitivity, mouse-profile import, modifier delivery, USB response handling and settings-window fixes from the October 12 audit. Release artifact: `OpenNaga-v2.5.0.dmg`, Apple Silicon, ad-hoc signed and not notarized; release notes in `Documentation/release-2.5.0.md`.
- 1009 dependency-free checks pass after the issue audit. Release compilation succeeds; dependency-free compilation emits the existing macOS 14 `onChange` deprecations. README screenshots use the synthetic `Everyday` profile (`.build/showcase-home`, `CFFIXED_USER_HOME`).
- Hardware evidence: on 2026-09-11 the Test profile was written and read back (21 descriptors), Escape on side button 1 survived a power cycle. On 2026-09-30 the DPI buttons were rewritten to DPI up/down, all 21 stored and active descriptors verified, and the user tested the saved profile over Bluetooth with the app closed and reported it works (tentative, not per-button).
- The user's journal `onboard-profile.json` was rebound from USB location `18026496` to `18022400` by hand before the model-based check existed; the original is `onboard-profile.port-0x01131000.bak.json` in Application Support.
- `--diagnose` run from a terminal fails with `0xe00002e2` (kIOReturnNotPermitted): the launching process needs Input Monitoring. Use `open -n OpenNaga.app --args --diagnose-file <path>` instead.

## Recent changes

- 2026-10-13 (#6 follow-up): modifiers the user holds while pressing a mapped control now combine with the mapped output (Command + side button mapped to C sends Command-C; keypad mappings too). The tap passes the triggering event's flags to `ButtonMapper.handlePress(buttonIndex:inputFlags:)`; driver-mode reports sample `CGEventSource.flagsState(.combinedSessionState)`. Modifiers OpenNaga holds itself, or released less than 50 ms earlier, are excluded so a synthetic Command cannot leak into the next press. Keypad keys now carry `maskNumericPad` like hardware events. 1020 checks; physical confirmation with Keyboard Maestro is pending.
- 2.5.0 (2026-10-12): package the audited fixes and new scroll/import features, bump the bundle to build 9, update the download instructions and document validation limits. Public DMGs use ad-hoc signing; the installed copy keeps the local development identity so TCC permissions remain stable.
- 2026-10-12: audited open issues #6/#7 and PRs #1 through #5. The automated modifier fix did not compile, and the scroll commit only added an unused helper. Fixed modifier API/state ownership, overlapping holds and macros; completed scroll settings, HID correlation and event scaling. Integrated USB callback timeout units, normal-layer reply normalization, safe mouse import, full sidebar hit areas and temporary Dock/Command-Tab presence. Added bounded GET_REPORT-only polling for valid busy/stale replies; uncertain writes are not resent on polling exhaustion. `.github/workflows/validate.yml` builds and runs the dependency-free suite on pushes and PRs. The external issue bot is not configured in this repository.
- 2026-10-12 validation: USB receiver `1532:00b4` read DPI 1600x1600, polling 1000 Hz, battery 93%, normal mode and all 21 stored/active bindings. Explicit same-value DPI/poll writes, a temporary F20 onboard save/restore and the production journaled driver-mode toggle/shutdown restore passed. All 21 original assignments and settings were restored. Six live synthetic shortcut combinations reached macOS with balanced modifiers. Light/dark minimum-size UI, blank sidebar-row clicks, close/reopen and activation-policy changes checked. See `Documentation/verification-2026-10-12.md` for evidence and limits; do not infer per-button or Bluetooth coverage from USB readback.
- 2026-10-07: README hero is an animated demo, `Documentation/demo-dark.gif` and `demo-light.gif`. Built from `--snapshot` renders of controls 1 to 19 with the synthetic `Everyday` profile in `.build/showcase-home`, cropped to the mouse, list and inspector (the sidebar and footer show "Mouse disconnected" without hardware), crossfaded, then `ffmpeg` palette and `gifsicle -O3`. `screenshot-light.png` and `screenshot-dark.png` stay because external list entries link to them.
- 2.4.0 (2026-10-04): DParent10, the NagaController author, reported that both apps wrote `~/Library/Application Support/NagaController/` with diverged profile formats, so each could rewrite the other's `profiles.json`. OpenNaga moved to its own folder (see `Utils/DataFolder`). The three releases titled "NagaController 2.x" were retitled, issues and private vulnerability reporting were enabled, and the README credits now list every protocol source (OpenRazer driver sources, PR 2850, issues 2845 and 2031, OpenSnek notes). He also asked to take `Hardware/` upstream; the owner's answer is not recorded here.
- 2026-10-04: README gained a `How it compares` table (OpenNaga, NagaController, SteerMouse) and a note on Razer Synapse for Mac, built from each project's own pages. The "5.7.2, USB connection only" note that search engines attribute to Synapse is from the SteerMouse release notes; Synapse for Mac still does not list this mouse. Recheck those pages before editing the table. Comments linking the repo were posted on Reddit and on `1kc/razer-macos` issues 739 and 926.
- 2.3.0: onboard memory. `Save to Mouse…` button next to the profile picker and `Mouse Memory…` menu item open `OnboardProfilePane`. Saving is explicit only (never on edit, profile switch, startup, refresh or quit). While a saved profile is active, software interception and driver mode are disabled; restoring the backup re-enables them. DPI up/down mouse actions exist only as hardware functions (software mapper ignores them). Onboard buttons 4/5 stay standard mouse buttons (user choice, for games). Backup identity now compares vendor:product only, because moving the dongle to another hub/port blocked save and restore.
- 2.2.0: rename to OpenNaga and English UI. Persisted identifiers unchanged; the default profile `Navigazione` became `Navigation`.
- 2.1.x: Bluetooth identity `068e:00b5` detection, System actions catalog (25 functions), native UI with mouse photo targets, keyboard key picker, background and hotplug fixes.

## Installed copy

On 2026-10-12 neither app nor either data folder existed on this Mac. Installed the audited source build as `/Applications/OpenNaga.app`, then updated it to 2.5.0 build 9 using the local `NagaController Dev` identity; application data remained byte-identical. The user granted Accessibility and Input Monitoring. Imported the live mouse's 19 editable assignments into the selected local `From Mouse` profile, retaining its `onboardOnly` protection. Hardware assignments and settings were restored after testing; no recovery journal remains. The bundle ID is unchanged; the app is not notarized. Keep only this installed copy, and quit it before replacing its bundle. Temporary audit fixtures and captures live under `.build/audit` and `/tmp/opennaga-*`; any pending test backup must be restored before further mouse writes.

## Preferences and constraints

- Everything in English: user-facing strings, code, comments, docs, commit messages. Do not reintroduce Italian strings.
- Native macOS light/dark appearance with restrained Razer green accents. Preserve transparent PNG alpha and the interactive mouse photo.
- No em dashes anywhere.
- MIT only: protocol knowledge from OpenRazer docs / PR 2850 and public protocol notes, no GPL code copied; OpenMouse is unlicensed, do not copy.
- Never change hardware settings on init or refresh; driver mode only through the explicit toggle, always journaled and restored. Onboard writes only on explicit Save or Restore, always with a backup.
- Local profiles are saved on the Mac; only an explicit Save to Mouse writes one profile to the mouse. Never describe edits or profile selection as synchronized to the mouse. Sequences, macros, scripts, app launch, profile switch and Fn shortcuts need the app.
- Do not claim signing or notarization that does not exist.
- The project is being promoted in Razer communities: keep README accurate, honest about what is verified, and free of filler.
- Automation must run `swift build -c release --product NagaController` and `bash Scripts/test.sh` before claiming a fix works. Mock checks and compilation do not prove physical mouse input, persistence across power cycles or Bluetooth behavior.

## Known issues / next steps

- Not notarized: users see a Gatekeeper warning. A Developer ID and notarization would remove it.
- USB driver-mode toggle/restore, all 21 onboard descriptor readbacks, a physical Command+Shift shortcut and native wheel/tilt scaling passed on 2026-10-12. Remaining physical checks: per-button onboard execution, software remapping over Bluetooth, power-cycle persistence of the new build, simultaneous physical/synthetic modifier changes and USB unplug/replug.
- System actions: Do Not Disturb needs a user-assigned shortcut; brightness depends on display support; media keys depend on the playback app.
- `onChange(of:perform:)` deprecation is tolerated because the deployment target is macOS 13.

## Do not

- Do not commit or push without an explicit request.
- Do not create feature branches or extra worktrees; work on `main`.
- Do not rename the bundle id or the dev signing identity; that would drop permissions. Do not move the data folder again without an import step.
- Do not write to, rename or delete `~/Library/Application Support/NagaController`; it belongs to the upstream app. Do not rerun the import once the marker exists.
- Do not reintroduce Italian user-facing strings or the NagaController name in the UI.
- Do not open the receiver with IOUSBHost exclusive access (conflicts with the system HID driver).
- Do not reintroduce the legacy neon card UI or global keyboard interception outside explicit shortcut recording.
- Do not add permanent stub models for UI compilation.
- Do not change macOS keyboard shortcuts automatically. Lock, sleep, shutdown and restart are outside the agreed System catalog.
- Do not write mouse flash on edits, startup, refresh, profile selection or quit. Do not delete `onboard-profile.json` to bypass recovery.
- Do not translate onboard mouse buttons 4/5 to browser shortcuts.
- Do not enable software remapping for profiles imported from custom mouse firmware or remove their `onboardOnly` metadata on duplication/export/import.
