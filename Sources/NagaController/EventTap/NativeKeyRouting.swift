import Foundation
import Carbon.HIToolbox

/// USB HID Usage Tables, Keyboard/Keypad page 0x07, mapped to macOS virtual
/// key codes. Modifier usages E0 through E7 and Caps Lock are deliberately
/// absent: they already reach macOS as flagsChanged events.
enum HIDKeyboardUsage {
    private static let table: [UInt32: Int] = [
        0x04: kVK_ANSI_A, 0x05: kVK_ANSI_B, 0x06: kVK_ANSI_C, 0x07: kVK_ANSI_D,
        0x08: kVK_ANSI_E, 0x09: kVK_ANSI_F, 0x0a: kVK_ANSI_G, 0x0b: kVK_ANSI_H,
        0x0c: kVK_ANSI_I, 0x0d: kVK_ANSI_J, 0x0e: kVK_ANSI_K, 0x0f: kVK_ANSI_L,
        0x10: kVK_ANSI_M, 0x11: kVK_ANSI_N, 0x12: kVK_ANSI_O, 0x13: kVK_ANSI_P,
        0x14: kVK_ANSI_Q, 0x15: kVK_ANSI_R, 0x16: kVK_ANSI_S, 0x17: kVK_ANSI_T,
        0x18: kVK_ANSI_U, 0x19: kVK_ANSI_V, 0x1a: kVK_ANSI_W, 0x1b: kVK_ANSI_X,
        0x1c: kVK_ANSI_Y, 0x1d: kVK_ANSI_Z,
        0x1e: kVK_ANSI_1, 0x1f: kVK_ANSI_2, 0x20: kVK_ANSI_3, 0x21: kVK_ANSI_4,
        0x22: kVK_ANSI_5, 0x23: kVK_ANSI_6, 0x24: kVK_ANSI_7, 0x25: kVK_ANSI_8,
        0x26: kVK_ANSI_9, 0x27: kVK_ANSI_0,
        0x28: kVK_Return, 0x29: kVK_Escape, 0x2a: kVK_Delete, 0x2b: kVK_Tab,
        0x2c: kVK_Space, 0x2d: kVK_ANSI_Minus, 0x2e: kVK_ANSI_Equal,
        0x2f: kVK_ANSI_LeftBracket, 0x30: kVK_ANSI_RightBracket, 0x31: kVK_ANSI_Backslash,
        0x33: kVK_ANSI_Semicolon, 0x34: kVK_ANSI_Quote, 0x35: kVK_ANSI_Grave,
        0x36: kVK_ANSI_Comma, 0x37: kVK_ANSI_Period, 0x38: kVK_ANSI_Slash,
        0x3a: kVK_F1, 0x3b: kVK_F2, 0x3c: kVK_F3, 0x3d: kVK_F4, 0x3e: kVK_F5, 0x3f: kVK_F6,
        0x40: kVK_F7, 0x41: kVK_F8, 0x42: kVK_F9, 0x43: kVK_F10, 0x44: kVK_F11, 0x45: kVK_F12,
        0x46: kVK_F13, 0x47: kVK_F14, 0x48: kVK_F15,
        0x49: kVK_Help, 0x4a: kVK_Home, 0x4b: kVK_PageUp, 0x4c: kVK_ForwardDelete,
        0x4d: kVK_End, 0x4e: kVK_PageDown,
        0x4f: kVK_RightArrow, 0x50: kVK_LeftArrow, 0x51: kVK_DownArrow, 0x52: kVK_UpArrow,
        0x53: kVK_ANSI_KeypadClear, 0x54: kVK_ANSI_KeypadDivide, 0x55: kVK_ANSI_KeypadMultiply,
        0x56: kVK_ANSI_KeypadMinus, 0x57: kVK_ANSI_KeypadPlus, 0x58: kVK_ANSI_KeypadEnter,
        0x59: kVK_ANSI_Keypad1, 0x5a: kVK_ANSI_Keypad2, 0x5b: kVK_ANSI_Keypad3,
        0x5c: kVK_ANSI_Keypad4, 0x5d: kVK_ANSI_Keypad5, 0x5e: kVK_ANSI_Keypad6,
        0x5f: kVK_ANSI_Keypad7, 0x60: kVK_ANSI_Keypad8, 0x61: kVK_ANSI_Keypad9,
        0x62: kVK_ANSI_Keypad0, 0x63: kVK_ANSI_KeypadDecimal,
        0x64: kVK_ISO_Section, 0x67: kVK_ANSI_KeypadEquals,
        0x68: kVK_F13, 0x69: kVK_F14, 0x6a: kVK_F15, 0x6b: kVK_F16,
        0x6c: kVK_F17, 0x6d: kVK_F18, 0x6e: kVK_F19, 0x6f: kVK_F20
    ]

    static func keyCode(forUsage usage: UInt32) -> CGKeyCode? {
        table[usage].map { CGKeyCode($0) }
    }

    /// Several usages can produce one key code, such as Print Screen and F13.
    static func usages(forKeyCode keyCode: CGKeyCode) -> [UInt32] {
        table.compactMap { CGKeyCode($0.value) == keyCode ? $0.key : nil }.sorted()
    }
}

/// macOS keeps modifier state per keyboard device, so a key the mouse sends
/// natively never carries the Command held on a separate keyboard. Such a key
/// is re-sent with the held modifiers. Once a key-down is re-sent, its
/// auto-repeats and key-up are re-sent too, so the pair stays on one source.
struct NativeKeyRouting {
    enum Decision: Equatable { case pass, reroute }
    private(set) var rerouted: Set<CGKeyCode> = []

    /// - Parameters:
    ///   - fromMouse: a matching HID edge from the mouse's keyboard interface.
    ///   - mouseHolds: the mouse currently holds a usage for this key code.
    ///   - missingModifiers: held modifiers absent from the native event.
    mutating func decide(keyCode: CGKeyCode, down: Bool, autorepeat: Bool, fromMouse: Bool,
                         mouseHolds: Bool, missingModifiers: CGEventFlags) -> Decision {
        if autorepeat {
            return down && mouseHolds && rerouted.contains(keyCode) ? .reroute : .pass
        }
        if down {
            guard fromMouse else { return .pass }
            if rerouted.contains(keyCode) { return .reroute }
            guard !missingModifiers.isEmpty else { return .pass }
            rerouted.insert(keyCode)
            return .reroute
        }
        // An uncorrelated key-up still closes a re-sent key once the mouse has
        // released it, so the synthetic source cannot keep it down.
        guard rerouted.contains(keyCode), fromMouse || !mouseHolds else { return .pass }
        rerouted.remove(keyCode)
        return .reroute
    }

    /// Returns the keys that still need a synthetic key-up.
    mutating func reset() -> [CGKeyCode] {
        defer { rerouted.removeAll() }
        return rerouted.sorted()
    }
}

/// Opt-in diagnostics for modifier delivery, enabled with
/// `defaults write com.zer0codestuff.NagaController ModifierTrace -bool true`.
/// Records only modifier edges and keys produced by the mouse, never ordinary
/// keyboard text, in ~/Library/Application Support/OpenNaga/modifier-trace.log.
enum ModifierTrace {
    static let defaultsKey = "ModifierTrace"
    static let fileName = "modifier-trace.log"
    static let maximumBytes = 1_000_000
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: defaultsKey) }
    private static let queue = DispatchQueue(label: "OpenNaga.ModifierTrace")

    static func hex(_ flags: CGEventFlags) -> String { "0x" + String(flags.rawValue, radix: 16) }

    static func log(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        queue.async {
            let url = DataFolder.file(fileName)
            try? FileManager.default.createDirectory(at: DataFolder.url, withIntermediateDirectories: true)
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
            if size > maximumBytes { try? FileManager.default.removeItem(at: url) }
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}
