# Held modifier follow-up, 2026-10-13

Issue [#6](https://github.com/Zer0codestuff/OpenNaga/issues/6) was reopened after a user tested 2.5.0 and reported that holding Command on the keyboard while pressing a side button mapped to plain C still produced C. Keypad mappings were also affected. The previous physical test used modifiers configured in the mouse mapping, which did not establish this separate behavior.

The external issue bot added commits `100c0b0` and `18fe902`. Their 1020 checks passed locally and on GitHub, but additional regressions failed before the corrective patch: `Plain c combines with aggregate-only physical modifier 55`.

## Corrective changes

- Modifier events without left/right device bits use per-key state instead of being treated as releases. A clear from one keyboard can coexist with a modifier held on another; owned synthetic keys are excluded from that fallback.
- A mapped key release uses current modifiers, rather than the physical flags captured when the button was pressed.
- Queued synthetic releases are acknowledged by their own marked event. No elapsed-time exclusion or comparison between timestamps from different event sources is used.
- Acknowledgment refreshes all managed aggregate and left/right modifier bits, preserving unrelated flags. A physical modifier pressed or released while the synthetic event is queued is reflected in the delivered release.
- Key events retain Quartz's native numeric-pad flag, including keypad and arrow keys.
- Event-tap and HID release paths forward current input flags. Tap recreation clears observations and pending acknowledgments.

`bash Scripts/test.sh`: **1093 checks passed**, including 125 modifier checks. The other suite counts are unchanged from the October 12 audit. `git diff --check` passed. Logs are `.build/modifier-regression-baseline.log` and `.build/modifier-regression-fixed.log`.

## Physical measurement

The receiver remains connected. A temporary development-signed probe runs the production input path with side button 6 mapped to plain C, using its existing factory-compatible 6-key assignment. No onboard assignments, DPI, polling settings or persisted profiles are changed by this probe.

The first capture of the bot build contained five C press/release pairs with no Command flag. It also contained no recorded physical Command event. The user reported holding Command, so this capture does not distinguish an input problem from a missing observation.

A second probe observes only raw modifier usages E0 through E7 on each keyboard device, plus flagsChanged provenance and the mapped output. It does not record ordinary keyboard text. Initial snapshots include the internal Apple keyboard and the receiver's keyboard collections.

The user repeated the letter test and confirmed the hardware status showed Command. The internal keyboard delivered usage E3 down/up and physical Command flagsChanged events. Three mapped C down/up pairs reached the session stream with Command, and all three key-downs reached the native test view with Command. The following press after releasing Command produced plain C in the session stream. The receiver's original 6-key events contained no Command flag, confirming that trigger flags alone are insufficient on this Mac; the production mapper retained the separately observed keyboard modifier. No independent physical-monitor override was injected into the mapper.

The keypad test produced five Keypad 6 press/release pairs. The first three pairs carried Command on both edges. On the fourth pair, the user released Command before the mouse button: key-down carried Command and key-up did not. The final pair was plain Keypad 6. All ten edges retained numeric-pad identity. The native test view received all four Command-Keypad 6 key-downs and the unmodified key-up after the inverse release order. Raw physical modifier state was empty at completion. The probe shut down cleanly and its temporary mapping was removed.

The probe is not Keyboard Maestro. Native onboard output and software remapping are separate paths; this investigation does not enable software remapping for imported custom firmware profiles. Issue #6 remains open for the original reporter's Keyboard Maestro confirmation. These changes are packaged as 2.5.1, build 10, for Apple Silicon, ad-hoc signed and not notarized. The DMG passed verification, read-only mounting, signature validation and executable comparison.

Temporary probe sources, binaries and captures are under `.build/audit` and `/tmp/opennaga-modifier-*`. Quit the probe before running or replacing the installed app.

## Installation

Installed 2.5.1 build 10 as the single `/Applications/OpenNaga.app`, preserving the development identity and its exact signing requirement. The previous bundle is retained under `.build/release-2.5.1` as a rollback checkpoint. Both Accessibility and Input Monitoring remained granted. `profiles.json` retained SHA-256 `8aee99c0b8e9bba32e252032f8723da7e9e3c820f027ea959c8399ced3a2f7bb`.

The installed app's read-only diagnostic returned receiver `1532:00b4`, DPI 1600x1600, polling 1000 Hz, battery 93%, mode 0, `readVerified: true`, no warnings and `writesRequested: false`. No recovery journal is pending.
