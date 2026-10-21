# OpenNaga 2.6.0

OpenNaga 2.6.0 adds a Hypershift layer that is also stored in mouse memory, following the discussion in [#6](https://github.com/Zer0codestuff/OpenNaga/issues/6).

- Each profile has a Standard and a Hypershift layer. Set a control's action to Hypershift key, then give other controls a second action used while you hold it.
- **Save to Mouse** writes both layers. The Hypershift key works with OpenNaga closed, after a power cycle and on other computers.
- Import from Mouse reads the Hypershift layer back into the profile.
- With a profile saved to or imported from the mouse, OpenNaga adds the modifiers you hold on the keyboard to the mouse's keys while it runs. Command plus a side button saved as Z gives Command-Z. Without the app, macOS delivers the mouse's keys without keyboard modifiers; no setting in the mouse can change that.

Validation: **1313 automated checks passed** and the release build compiled. On the USB receiver, a profile with side button 1 as Hypershift key produced its Hypershift actions with the app closed and after switching the mouse off and on, and Command plus a saved side button produced Command-Z while the app ran. Restoring returned all 84 stored assignments to their previous bytes. See the [verification record](https://github.com/Zer0codestuff/OpenNaga/blob/main/Documentation/verification-2026-10-21.md).

Not verified: Hypershift over Bluetooth and Keyboard Maestro.

Upgrade: quit OpenNaga and replace the app in Applications. Profiles and mouse backups remain in `~/Library/Application Support/OpenNaga`. Public builds are ad-hoc signed and not notarized; macOS may request Accessibility and Input Monitoring again after replacement. The downloadable build is Apple Silicon for macOS 13 or later. `SHA256SUMS.txt` contains the DMG checksum.
