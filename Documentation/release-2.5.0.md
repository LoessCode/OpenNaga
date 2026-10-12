# OpenNaga 2.5.0

OpenNaga 2.5.0 adds independent vertical and horizontal scroll sensitivity, imports assignments from mouse memory, and fixes modifier shortcuts and USB communication.

- **Modifier shortcuts:** fix Command, Control, Shift and Option delivery for held buttons, key sequences and macros. Preserve physical left/right modifiers and overlapping holds. Resolves [#6](https://github.com/Zer0codestuff/OpenNaga/issues/6).
- **Scroll sensitivity:** separate vertical-wheel and horizontal/tilt sliders from 0.1x to 5x, with persistent settings and Reset. Scales native wheel input and assigned scroll actions while software remapping is enabled. Trackpad and momentum scrolling are unchanged. Resolves [#7](https://github.com/Zer0codestuff/OpenNaga/issues/7).
- **Import from Mouse:** read supported onboard assignments into an editable local profile. Imported profiles keep software remapping paused because custom firmware events cannot reliably identify physical controls. Use Save to Mouse to apply edits. Import performs no hardware writes and reports unsupported assignments.
- **USB and mouse memory:** correct HID callback timeout units, normalize onboard reply metadata while keeping writes on the normal layer, and wait for valid delayed receiver responses without resending uncertain writes.
- **Settings window:** appears in the Dock and Command-Tab while open, then returns to a menu bar accessory when closed. The entire sidebar row is clickable.

Thanks to [stets](https://github.com/stets) for PRs [#1](https://github.com/Zer0codestuff/OpenNaga/pull/1), [#2](https://github.com/Zer0codestuff/OpenNaga/pull/2), [#3](https://github.com/Zer0codestuff/OpenNaga/pull/3), [#4](https://github.com/Zer0codestuff/OpenNaga/pull/4) and [#5](https://github.com/Zer0codestuff/OpenNaga/pull/5), and to the users who reported the modifier and scroll issues.

Validation: **1009 automated checks passed locally and on GitHub**. Tests on a Naga V2 HyperSpeed USB receiver covered physical modifier delivery, wheel/tilt scaling, DPI and polling readback, onboard save/restore and the driver-mode recovery path. All 21 original assignments and settings were restored after testing. Bluetooth software remapping, execution of every individual onboard button, power-cycle persistence of this build and receiver reconnect remain unverified. See the [verification record](https://github.com/Zer0codestuff/OpenNaga/blob/main/Documentation/verification-2026-10-12.md).

Upgrade: quit OpenNaga and replace the app in Applications with the new `OpenNaga.app`. Profiles and mouse backups remain in `~/Library/Application Support/OpenNaga`. Scroll sensitivity stays on the Mac and is not written to mouse memory. macOS may ask for Accessibility and Input Monitoring again after replacing an ad-hoc signed build.

Apple Silicon build for macOS 13 or later, ad-hoc signed and not notarized. On first launch right-click the app and choose Open, or run `xattr -dr com.apple.quarantine /Applications/OpenNaga.app`. `SHA256SUMS.txt` contains the checksum of the DMG.
