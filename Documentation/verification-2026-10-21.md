# Issue #6 follow-up and onboard Hypershift, 2026-10-21

Issue [#6](https://github.com/Zer0codestuff/OpenNaga/issues/6) asked for keyboard modifiers to combine with the mouse's side buttons. The reporter's last comment clarified the goal: modifiers combining with the mouse's own keys without OpenNaga running. After 2.5.1 the external issue bot pushed `f4c3b98` (re-send native mouse keys with held modifiers) and `951b988` (software Hypershift layer) without hardware tests.

## Findings

- macOS keeps modifier state per keyboard device. With OpenNaga closed, holding Command on the internal keyboard and pressing side button 4 (stored as Z) delivered a plain Z. No mouse-side write can change this; the request is not possible without software.
- `f4c3b98` never activated where the reporter needed it. `EventTapManager.start` required `listenOnly && onboard && getRemappingEnabled()`, but `getRemappingEnabled()` is false for imported profiles, and the launch path passes `listenOnly: false` for a saved mouse profile. The installed-app trace logged `nativeModifiers=false onboard=true`.
- Its mechanism works when active: with a normal profile, Remapping on and side button 4 unmapped, Command plus side button 4 reached a test window as Command-Z sent by OpenNaga, then plain Z after releasing Command.
- The firmware has a second assignment layer (request byte 2 = 1) in both banks, holding factory values: side buttons send 1 through =, the top buttons DPI up and down.
- Function block `0c 01 01` on a control makes it a hold-to-shift key. While held, the other controls use their layer 1 entries; after release they return to the normal layer. `0c 01 00` also switched layers while held; its release behavior was not checked. `0c 01 02` stayed latched after release until the mouse was switched off and on; OpenNaga never writes it.
- Writing a control's layer 1 entry sets reply byte 2 to 01 on that control in both layers and banks. A later normal-layer write, including a same-value write, clears it. Function bytes are unaffected. OpenNaga now writes layer 1 first and then the normal layer of every control it touched.

## Changes

- Mouse-memory and imported profiles always merge held keyboard modifiers into native mouse keys while the app runs; other profiles follow the Remapping switch. The tap restarts when only this state changes.
- Save to Mouse writes the Hypershift key (`0c 01 01`) and the Hypershift layer. Controls without a Hypershift action mirror their standard function. The journal adds `originalHypershift`, captured before OpenNaga first writes that layer; journals without it still load. Restore and rollback cover both layers. A profile without a Hypershift key never reads or writes layer 1 unless an earlier save changed it, in which case layer 1 returns to the backup.
- Import from Mouse reads layer 1 when the normal layer has a Hypershift key and keeps entries that differ from the standard layer.
- The left click cannot be the Hypershift key in mouse memory. DPI up and down are allowed in the Hypershift layer.

`bash Scripts/test.sh`: **1313 checks passed**. `swift build -c release --product NagaController` passed.

## Hardware evidence

USB receiver `1532:00b4`, DPI 1600x1600, polling 1000 Hz, mode 0. A test profile lived in an isolated home (`CFFIXED_USER_HOME=.build/hs-home`) and was saved and restored through the production `--save-onboard-profile` and `--restore-onboard-profile` paths. The test window recorded key events delivered to an app.

Profile: side button 1 as Hypershift key, wheel click J and wheel tilt left K in the Hypershift layer, all other controls unchanged.

| Check | Result |
| --- | --- |
| App closed, hold side 1 and click wheel | J |
| App closed, hold side 1 and tilt wheel left | K |
| App closed, wheel click alone | no key |
| After switching the mouse off and on, hold side 1 and click wheel | J |
| App running with the saved profile, Command plus side 4 | Command-Z sent by OpenNaga; trace `nativeModifiers=true onboard=true` |
| Command released, side 4 | Z |
| Restore, then read 2 banks x 2 layers x 21 controls | all 84 bindings identical to the pre-test backup, byte 2 included |

An earlier save with side button 1 as Hypershift key also produced J and K from side buttons 4 and 5 while held, and Z alone. A save with both top buttons as Hypershift keys was restored with the new write order and also matched the backup byte for byte.

Not verified: Hypershift over Bluetooth, Keyboard Maestro, and modifier merging with an unplugged and replugged receiver. Probe sources, logs and the binding backup are under `.build/audit`.
