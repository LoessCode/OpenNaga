# OpenNaga 2.5.1

OpenNaga 2.5.1 fixes held keyboard modifiers combining with software-mapped mouse buttons, following the additional report in [#6](https://github.com/Zer0codestuff/OpenNaga/issues/6).

- Hold Command on the keyboard and press a button mapped to plain C to send Command-C. Trigger flags and physical modifier observations combine with the mapping's own modifiers.
- Releasing the keyboard modifier before the mouse button no longer restores the modifier on key-up.
- Replace the 50 ms synthetic-release exclusion with acknowledgment of the posted release. New physical presses are accepted immediately, and queued releases reflect current modifier ownership.
- Preserve native numeric-pad identification on keypad and arrow keys.

Validation: **1093 automated checks passed**, and the release executable compiled. USB physical tests delivered Command-C and Command-Keypad 6, followed by plain keys after releasing Command. Releasing Command before the mouse button cleared it on key-up, and every keypad event retained its numeric-pad identity. See the [verification record](https://github.com/Zer0codestuff/OpenNaga/blob/main/Documentation/verification-2026-10-13.md).

Held-modifier combining applies while software remapping is enabled. Profiles saved to mouse memory or imported from custom firmware retain their existing protection and native behavior. No profiles or mouse settings are changed by this update. Keyboard Maestro confirmation from the original reporter, Bluetooth software remapping and receiver reconnect remain unverified.

Upgrade: quit OpenNaga and replace the app in Applications. Profiles and mouse backups remain in `~/Library/Application Support/OpenNaga`. Public builds are ad-hoc signed and not notarized; macOS may request Accessibility and Input Monitoring again after replacement. The downloadable build is Apple Silicon for macOS 13 or later. `SHA256SUMS.txt` contains the DMG checksum.
