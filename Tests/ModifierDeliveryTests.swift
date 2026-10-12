import Cocoa
import Carbon.HIToolbox

enum ModifierDeliveryTests {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    @MainActor
    static func run() async throws -> Int {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            guard condition() else { throw Failure(description: message) }
            count += 1
        }
        func physicalEdge(code: CGKeyCode, flags: CGEventFlags) -> CGEvent {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: !flags.isEmpty)!
            event.type = .flagsChanged
            event.flags = flags
            return event
        }
        let physicalKeys: [(CGKeyCode, String, CGEventFlags)] = [
            (CGKeyCode(kVK_Command), "cmd", .maskCommand),
            (CGKeyCode(kVK_RightCommand), "cmd", .maskCommand),
            (CGKeyCode(kVK_Control), "ctrl", .maskControl),
            (CGKeyCode(kVK_RightControl), "ctrl", .maskControl),
            (CGKeyCode(kVK_Shift), "shift", .maskShift),
            (CGKeyCode(kVK_RightShift), "shift", .maskShift),
            (CGKeyCode(kVK_Option), "alt", .maskAlternate),
            (CGKeyCode(kVK_RightOption), "alt", .maskAlternate),
            (CGKeyCode(kVK_Function), "fn", .maskSecondaryFn)
        ]
        for (code, name, flag) in physicalKeys {
            var events: [CGEvent] = []
            let mapper = ButtonMapper(eventSink: { events.append($0) })
            mapper.modifierKeyState = { $0 == code }
            mapper.updateMapping([1: .keySequence(keys: [KeyStroke(key: "c", modifiers: [name])], description: nil)])
            mapper.handle(buttonIndex: 1)
            try check(events.map(\.type) == [.keyDown, .keyUp], "Physical modifier \(code) is borrowed without synthetic edges")
            try check(events.allSatisfy { $0.flags.contains(flag) }, "Borrowed physical modifier \(code) remains on both key edges")
        }

        var events: [CGEvent] = []
        let mapper = ButtonMapper(eventSink: { events.append($0) })
        mapper.modifierKeyState = { _ in false }
        mapper.updateMapping([
            1: .keySequence(keys: [KeyStroke(key: "c", modifiers: ["cmd"])], description: nil),
            2: .keySequence(keys: [KeyStroke(key: "v", modifiers: ["shift"])], description: nil)
        ])
        mapper.handlePress(buttonIndex: 1)
        mapper.handlePress(buttonIndex: 2)
        try check(events[2].flags.contains([.maskCommand, .maskShift]), "New modifier edge preserves an existing held modifier")
        try check(events[3].flags.contains([.maskCommand, .maskShift]), "Overlapping key holds carry all active modifiers")
        mapper.handleRelease(buttonIndex: 1)
        try check(events[4].flags.contains([.maskCommand, .maskShift]) && events[5].flags == .maskShift,
                  "Releasing one hold keeps the remaining modifier on key and modifier edges")
        mapper.handleRelease(buttonIndex: 2)
        try check(events.last?.flags == [], "Overlapping holds release all owned modifiers")

        events.removeAll()
        mapper.updateMapping([
            1: .keySequence(keys: [KeyStroke(key: "c", modifiers: ["cmd"])], description: nil),
            2: .keySequence(keys: [KeyStroke(key: "c", modifiers: ["cmd"])], description: nil)
        ])
        mapper.handlePress(buttonIndex: 1)
        mapper.handlePress(buttonIndex: 2)
        try check(events.count == 2, "Two controls holding the same key share one key press")
        mapper.handleRelease(buttonIndex: 1)
        try check(events.count == 2, "A shared held key stays pressed after the first control releases")
        mapper.handleRelease(buttonIndex: 2)
        try check(events.map(\.type) == [.flagsChanged, .keyDown, .keyUp, .flagsChanged], "The last shared hold balances key and modifier edges")

        events.removeAll()
        mapper.updateMapping([
            1: .keySequence(keys: [KeyStroke(key: "c", modifiers: ["cmd"])], description: nil),
            2: .keySequence(keys: [KeyStroke(key: "c", modifiers: ["ctrl"]), KeyStroke(key: "v", modifiers: ["cmd"])], description: nil)
        ])
        mapper.handlePress(buttonIndex: 1)
        mapper.handle(buttonIndex: 2)
        let cEvents = events.filter { $0.getIntegerValueField(.keyboardEventKeycode) == kVK_ANSI_C }
        try check(cEvents.map(\.type) == [.keyDown, .keyDown], "A sequence does not release a key held by another control")
        try check(cEvents.last?.getIntegerValueField(.keyboardEventAutorepeat) == 1, "A sequence retrigger of a held key is marked as repeat")
        try check(cEvents.last?.flags.contains([.maskCommand, .maskControl]) == true, "Sequence strokes preserve other held modifiers")
        mapper.releaseAll()
        try check(events.last?.flags == [], "Sequence and hold cleanup leaves no owned modifier")

        events.removeAll()
        mapper.updateMapping([1: .keySequence(keys: [KeyStroke(key: "c", modifiers: ["cmd"])], description: nil)])
        mapper.handlePress(buttonIndex: 1)
        let physicalCommand: CGEventFlags = [.maskCommand, CGEventFlags(rawValue: 0x08)]
        mapper.observePhysicalModifier(physicalEdge(code: CGKeyCode(kVK_Command), flags: physicalCommand))
        mapper.handleRelease(buttonIndex: 1)
        try check(events.last?.flags == physicalCommand, "A physical Command pressed during a synthetic hold survives its release")
        mapper.observePhysicalModifier(physicalEdge(code: CGKeyCode(kVK_Command), flags: []))
        events.removeAll()
        mapper.handle(buttonIndex: 1)
        try check(events.count == 4 && events.last?.flags == [], "A later physical release does not leave stale modifier ownership")

        events.removeAll()
        mapper.handlePress(buttonIndex: 1)
        mapper.observePhysicalModifier(physicalEdge(code: CGKeyCode(kVK_RightShift), flags: [.maskShift, CGEventFlags(rawValue: 0x04)]))
        mapper.handleRelease(buttonIndex: 1)
        try check(events[2].flags.contains([.maskCommand, .maskShift]), "Key release preserves an unrelated physical modifier")
        try check(events.last?.flags.contains(.maskShift) == true && events.last?.flags.contains(.maskCommand) == false,
                  "Synthetic modifier release preserves physical right Shift")
        mapper.observePhysicalModifier(physicalEdge(code: CGKeyCode(kVK_RightShift), flags: []))

        var borrowedEvents: [CGEvent] = []
        let borrowed = ButtonMapper(eventSink: { borrowedEvents.append($0) })
        borrowed.modifierKeyState = { $0 == CGKeyCode(kVK_Command) }
        borrowed.updateMapping([1: .keySequence(keys: [KeyStroke(key: "c", modifiers: ["cmd"])], description: nil)])
        borrowed.handlePress(buttonIndex: 1)
        borrowed.observePhysicalModifier(physicalEdge(code: CGKeyCode(kVK_Command), flags: []))
        try check(borrowedEvents.map(\.type) == [.keyDown, .flagsChanged], "Releasing a borrowed physical modifier reasserts the modifier a hold still requires")
        borrowed.handleRelease(buttonIndex: 1)
        try check(borrowedEvents.last?.flags == [], "A reasserted modifier is released with its final hold")

        events.removeAll()
        let ignored = physicalEdge(code: CGKeyCode(kVK_Command), flags: physicalCommand)
        ignored.setIntegerValueField(.eventSourceUserData, value: ButtonMapper.syntheticMarker)
        mapper.observePhysicalModifier(ignored)
        mapper.handle(buttonIndex: 1)
        try check(events.count == 4 && events.last?.flags == [], "Synthetic modifier edges cannot be mistaken for physical ownership")

        events.removeAll()
        mapper.modifierKeyState = { $0 == CGKeyCode(kVK_RightCommand) }
        mapper.resetPhysicalModifierObservation()
        mapper.handle(buttonIndex: 1)
        try check(events.map(\.type) == [.keyDown, .keyUp], "Restarting modifier observation refreshes keys changed while a tap was stopped")
        mapper.modifierKeyState = { _ in false }
        mapper.resetPhysicalModifierObservation()

        events.removeAll()
        mapper.runMacro([
            MacroStep(type: "key", keyStroke: KeyStroke(key: "c", modifiers: ["cmd"])),
            MacroStep(type: "delay", delayMs: 10),
            MacroStep(type: "key", keyStroke: KeyStroke(key: "v", modifiers: ["ctrl", "shift"]))
        ])
        for _ in 0..<100 where events.count < 10 { try await Task.sleep(nanoseconds: 5_000_000) }
        try check(events.count == 10, "Macro key steps emit balanced modifier and key edges across a delay")
        try check(events[1].flags == .maskCommand && events[6].flags == [.maskControl, .maskShift], "Each macro key step receives its own modifiers")
        try check(events.last?.flags == [], "Macro completion leaves no synthetic modifiers")

        events.removeAll()
        mapper.runMacro([MacroStep(type: "delay", delayMs: 30), MacroStep(type: "key", keyStroke: KeyStroke(key: "c", modifiers: ["cmd"]))])
        try await Task.sleep(nanoseconds: 5_000_000)
        mapper.updateMapping([:])
        try await Task.sleep(nanoseconds: 50_000_000)
        try check(events.isEmpty, "Changing mappings cancels delayed macro steps before modifier injection")
        return count
    }
}
