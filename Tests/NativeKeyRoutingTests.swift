import Cocoa
import Carbon.HIToolbox

/// Keys the mouse sends natively (mouse-memory profiles, unmapped buttons)
/// arrive without modifiers held on another keyboard, because macOS keeps
/// modifier state per keyboard device. Issue #6.
enum NativeKeyRoutingTests {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func run() throws -> Int {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            guard condition() else { throw Failure(description: message) }
            count += 1
        }
        let c = CGKeyCode(kVK_ANSI_C)
        let keypad6 = CGKeyCode(kVK_ANSI_Keypad6)
        let command = CGEventFlags.maskCommand

        // HID keyboard usages.
        try check(HIDKeyboardUsage.keyCode(forUsage: 0x06) == c, "HID usage 06 is C")
        try check(HIDKeyboardUsage.keyCode(forUsage: 0x5e) == keypad6, "HID usage 5E is Keypad 6")
        try check(HIDKeyboardUsage.keyCode(forUsage: 0x1e) == CGKeyCode(kVK_ANSI_1), "HID usage 1E is the side grid's 1")
        try check(HIDKeyboardUsage.keyCode(forUsage: 0x58) == CGKeyCode(kVK_ANSI_KeypadEnter), "HID usage 58 is Keypad Enter")
        try check(HIDKeyboardUsage.keyCode(forUsage: 0x52) == CGKeyCode(kVK_UpArrow), "HID usage 52 is Up Arrow")
        try check(HIDKeyboardUsage.usages(forKeyCode: CGKeyCode(kVK_F13)) == [0x46, 0x68], "Print Screen and F13 both resolve to F13")
        try check(HIDKeyboardUsage.usages(forKeyCode: c) == [0x06], "C resolves to one usage")
        for usage in UInt32(0xe0)...UInt32(0xe7) {
            try check(HIDKeyboardUsage.keyCode(forUsage: usage) == nil, "Modifier usage \(usage) is left to flagsChanged")
        }
        try check(HIDKeyboardUsage.keyCode(forUsage: 0x39) == nil, "Caps Lock is not re-sent")
        try check(HIDKeyboardUsage.keyCode(forUsage: 0x01) == nil, "Error roll-over is ignored")
        for usage in UInt32(0x04)...UInt32(0x6f) {
            guard let code = HIDKeyboardUsage.keyCode(forUsage: usage) else { continue }
            try check(HIDKeyboardUsage.usages(forKeyCode: code).contains(usage), "Usage \(usage) round-trips through key code \(code)")
        }

        // Routing decisions.
        var routing = NativeKeyRouting()
        try check(routing.decide(keyCode: c, down: true, autorepeat: false, fromMouse: true, mouseHolds: true, missingModifiers: command) == .reroute,
                  "A native mouse C with Command held on the keyboard is re-sent")
        try check(routing.decide(keyCode: c, down: true, autorepeat: true, fromMouse: false, mouseHolds: true, missingModifiers: command) == .reroute,
                  "Auto-repeat of a re-sent key stays on the synthetic source")
        try check(routing.decide(keyCode: c, down: false, autorepeat: false, fromMouse: true, mouseHolds: false, missingModifiers: []) == .reroute,
                  "The key-up of a re-sent key is re-sent even after Command was released")
        try check(routing.rerouted.isEmpty, "A completed re-sent key leaves no state")

        try check(routing.decide(keyCode: c, down: true, autorepeat: false, fromMouse: true, mouseHolds: true, missingModifiers: []) == .pass,
                  "A native mouse key without held modifiers passes untouched")
        try check(routing.decide(keyCode: c, down: true, autorepeat: true, fromMouse: false, mouseHolds: true, missingModifiers: []) == .pass,
                  "Auto-repeat of an untouched key passes")
        try check(routing.decide(keyCode: c, down: false, autorepeat: false, fromMouse: true, mouseHolds: false, missingModifiers: []) == .pass,
                  "The key-up of an untouched key passes")

        try check(routing.decide(keyCode: c, down: true, autorepeat: false, fromMouse: false, mouseHolds: false, missingModifiers: command) == .pass,
                  "A keyboard key is never re-sent")
        try check(routing.rerouted.isEmpty, "A keyboard key leaves no state")

        _ = routing.decide(keyCode: keypad6, down: true, autorepeat: false, fromMouse: true, mouseHolds: true, missingModifiers: command)
        try check(routing.decide(keyCode: keypad6, down: true, autorepeat: true, fromMouse: false, mouseHolds: false, missingModifiers: command) == .pass,
                  "Auto-repeat is not re-sent once the mouse no longer holds the key")
        try check(routing.decide(keyCode: keypad6, down: false, autorepeat: false, fromMouse: false, mouseHolds: true, missingModifiers: []) == .pass,
                  "A keyboard key-up for the same code passes while the mouse still holds it")
        try check(routing.rerouted == [keypad6], "The mouse's re-sent key remains open")
        try check(routing.decide(keyCode: keypad6, down: true, autorepeat: false, fromMouse: true, mouseHolds: true, missingModifiers: []) == .reroute,
                  "A repeated mouse key-down keeps the open key on the synthetic source")
        try check(routing.decide(keyCode: keypad6, down: false, autorepeat: false, fromMouse: false, mouseHolds: false, missingModifiers: []) == .reroute,
                  "An uncorrelated key-up closes a re-sent key the mouse released")
        try check(routing.rerouted.isEmpty, "The uncorrelated key-up cleared the open key")

        _ = routing.decide(keyCode: keypad6, down: true, autorepeat: false, fromMouse: true, mouseHolds: true, missingModifiers: command)
        _ = routing.decide(keyCode: c, down: true, autorepeat: false, fromMouse: true, mouseHolds: true, missingModifiers: command)
        try check(routing.reset() == [c, keypad6].sorted(), "Reset reports every open re-sent key for release")
        try check(routing.rerouted.isEmpty, "Reset clears open keys")

        // Held modifiers missing from a native event.
        var commandDown = true
        let mapper = ButtonMapper(eventSink: { _ in })
        mapper.modifierKeyState = { commandDown && $0 == CGKeyCode(kVK_Command) }
        let missing = mapper.heldModifiersMissing(from: [])
        try check(missing.contains(command) && missing.rawValue & 0x08 != 0, "Held left Command is missing from a plain mouse key")
        try check(mapper.heldModifiersMissing(from: command).isEmpty, "A mouse key that already carries Command needs nothing")
        let shiftMissing = mapper.heldModifiersMissing(from: .maskShift)
        try check(shiftMissing.contains(command) && !shiftMissing.contains(.maskShift), "Only absent modifiers are reported")
        commandDown = false
        let release = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Command), keyDown: false)!
        release.type = .flagsChanged
        release.flags = []
        mapper.observePhysicalModifier(release)
        try check(mapper.heldModifiersMissing(from: []).isEmpty, "Nothing is missing after Command is released")

        let owner = ButtonMapper(eventSink: { _ in })
        owner.modifierKeyState = { _ in false }
        owner.updateMapping([1: .keySequence(keys: [KeyStroke(key: "c", modifiers: ["cmd"])], description: nil)])
        owner.handlePress(buttonIndex: 1)
        try check(owner.heldModifiersMissing(from: []).isEmpty, "A Command owned by an active mapping is not merged into native keys")
        owner.releaseAll()

        // Delivery of a re-sent native key.
        var events: [CGEvent] = []
        let sender = ButtonMapper(eventSink: { events.append($0) })
        sender.modifierKeyState = { $0 == CGKeyCode(kVK_Command) }
        sender.postNativeKey(c, flags: [], down: true)
        sender.postNativeKey(c, flags: [], down: true, autorepeat: true)
        sender.postNativeKey(c, flags: [], down: false)
        try check(events.map(\.type) == [.keyDown, .keyDown, .keyUp], "A re-sent key keeps its down, repeat and up edges")
        try check(events.allSatisfy { $0.flags.contains(command) }, "Every re-sent edge carries the held Command")
        try check(events.allSatisfy { CGKeyCode($0.getIntegerValueField(.keyboardEventKeycode)) == c }, "The re-sent key code is unchanged")
        try check(events.allSatisfy { $0.getIntegerValueField(.eventSourceUserData) == ButtonMapper.syntheticMarker },
                  "Re-sent keys are marked so the tap does not process them again")
        try check(events[1].getIntegerValueField(.keyboardEventAutorepeat) == 1 && events[0].getIntegerValueField(.keyboardEventAutorepeat) == 0,
                  "Only the repeat edge is flagged as auto-repeat")
        events.removeAll()
        sender.postNativeKey(keypad6, flags: [], down: true)
        sender.postNativeKey(keypad6, flags: [], down: false)
        try check(events.allSatisfy { $0.flags.contains(.maskNumericPad) && $0.flags.contains(command) },
                  "A re-sent keypad key keeps its numeric-pad identity with Command")
        events.removeAll()
        sender.modifierKeyState = { _ in false }
        sender.postNativeKey(c, flags: .maskAlphaShift, down: false)
        try check(events.count == 1 && !events[0].flags.contains(command) && events[0].flags.contains(.maskAlphaShift),
                  "A key-up after Command is released carries only the remaining flags")

        try check(ModifierTrace.hex(command) == "0x100000", "Trace formats flags in hexadecimal")
        try check(ModifierTrace.defaultsKey == "ModifierTrace" && ModifierTrace.fileName == "modifier-trace.log", "Trace switch and file name are stable")
        return count
    }
}
