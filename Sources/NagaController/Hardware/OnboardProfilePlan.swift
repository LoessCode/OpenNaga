import Cocoa

struct OnboardProfilePlan {
    let name: String
    var functions: [UInt8: [UInt8]] = [:]
    var issues: [String] = []
    var isSupported: Bool { !functions.isEmpty && issues.isEmpty }

    // Grid IDs increase with the printed button numbers, not enumeration order.
    static let buttonIDs: [Int: UInt8] = Dictionary(uniqueKeysWithValues:
        (1...12).map { ($0, UInt8(0x40 + $0 - 1)) } +
        [(13, 0x0b), (14, 0x0c), (15, 0x34), (16, 0x35), (17, 3), (18, 1), (19, 2)])

    init(name: String, mapping: [Int: ActionType]) {
        self.name = name
        for index in mapping.keys.sorted() {
            guard let id = Self.buttonIDs[index], let action = mapping[index] else {
                issues.append("Button \(index): unknown hardware control."); continue
            }
            do { functions[id] = try Self.function(action) }
            catch { issues.append("Button \(index): \(error.localizedDescription)") }
        }
        if mapping.isEmpty { issues.append("The profile is empty.") }
    }

    private static func unsupported(_ text: String) -> RazerHardwareError { .invalidValue(text) }

    static func function(_ action: ActionType) throws -> [UInt8] {
        switch action {
        case .disabled: return Array(repeating: 0, count: 7)
        case .keySequence(let keys, _):
            guard keys.count == 1, let key = keys.first else { throw unsupported("key sequences need the app.") }
            return try keyboard(key)
        case .textSnippet(let text, _):
            guard text.count == 1, let key = KeyboardKeyCatalog.current().first(where: {
                [.letters, .numbers, .symbols].contains($0.group) && $0.key == text
            }) else { throw unsupported("the text cannot be typed as a single key in the current layout.") }
            return try keyboard(key.stroke())
        case .mouse(let mouse, _):
            switch mouse {
            case .dpiUp: return [6, 1, 1, 0, 0, 0, 0]
            case .dpiDown: return [6, 1, 2, 0, 0, 0, 0]
            case .leftClick: return [1, 1, 1, 0, 0, 0, 0]
            case .rightClick: return [1, 1, 2, 0, 0, 0, 0]
            case .middleClick: return [1, 1, 3, 0, 0, 0, 0]
            case .button4: return [1, 1, 4, 0, 0, 0, 0]
            case .button5: return [1, 1, 5, 0, 0, 0, 0]
            case .scrollUp: return [1, 1, 9, 0, 0, 0, 0]
            case .scrollDown: return [1, 1, 10, 0, 0, 0, 0]
            case .scrollLeft: return [0x0e, 3, 0x68, 0, 0x14, 0, 0]
            case .scrollRight: return [0x0e, 3, 0x69, 0, 0x14, 0, 0]
            case .browserBack, .browserForward:
                guard let stroke = KeyboardLayoutShortcut.browserStroke(for: mouse) else { throw unsupported("browser shortcut not available.") }
                return try keyboard(stroke)
            }
        case .audio(let action, _): return try system(SystemAction(audio: action))
        case .system(let action, _): return try system(action)
        case .application, .systemCommand, .macro, .profileSwitch:
            throw unsupported("this action needs OpenNaga running.")
        }
    }

    // Imported profiles run on the mouse, so retain native assignments too.
    // Software cannot identify physical buttons from arbitrary firmware outputs.
    static func mapping(from functions: [UInt8: [UInt8]]) -> (mapping: [Int: ActionType], issues: [String]) {
        var mapping: [Int: ActionType] = [:]
        var issues: [String] = []
        for (index, id) in buttonIDs.sorted(by: { $0.key < $1.key }) {
            guard let function = functions[id] else { continue }
            if let action = action(from: function) {
                mapping[index] = action
            } else if function.count == 7, function[0] == 2, (0xe0...0xe7).contains(function[3]) {
                issues.append("Button \(index): a modifier key on its own cannot be imported.")
            } else {
                issues.append("Button \(index): unsupported assignment \(function.map { String(format: "%02x", $0) }.joined(separator: " ")).")
            }
        }
        // Wheel rotation has no editable button index. Report a custom binding
        // rather than presenting a partial import as a complete editable layout.
        let wheelDefaults: [UInt8: [UInt8]] = [9: [1, 1, 9, 0, 0, 0, 0], 10: [1, 1, 10, 0, 0, 0, 0]]
        let editable = Set(buttonIDs.values)
        for id in functions.keys.sorted() where !editable.contains(id) {
            guard functions[id] != wheelDefaults[id] else { continue }
            issues.append(String(format: "Control 0x%02x: this assignment cannot be edited in OpenNaga.", id))
        }
        return (mapping, issues)
    }

    static func action(from function: [UInt8]) -> ActionType? {
        guard function.count == 7 else { return nil }
        if function.allSatisfy({ $0 == 0 }) { return .disabled }
        let action: ActionType?
        switch (function[0], function[1]) {
        case (1, 1):
            let buttons: [UInt8: MouseAction] = [1: .leftClick, 2: .rightClick, 3: .middleClick, 4: .button4,
                                                 5: .button5, 9: .scrollUp, 10: .scrollDown]
            action = buttons[function[2]].map { .mouse(action: $0, description: nil) }
        case (6, 1):
            let stages: [UInt8: MouseAction] = [1: .dpiUp, 2: .dpiDown]
            action = stages[function[2]].map { .mouse(action: $0, description: nil) }
        case (0x0e, 3):
            let tilt: [UInt8: MouseAction] = [0x68: .scrollLeft, 0x69: .scrollRight]
            action = tilt[function[2]].map { .mouse(action: $0, description: nil) }
        case (0x0a, 2):
            action = media.first { $0.value == function[3] }.map { .system(action: $0.key, description: nil) }
        case (2, 1), (2, 2):
            // Factory bindings use length 1 without a modifier byte but keep the usage in function[3].
            let mask = function[1] == 2 ? function[2] : 0
            guard mask & 0xf0 == 0, let code = keyboardCodes[function[3]] else { return nil }
            let bits: [(UInt8, String)] = [(1, "ctrl"), (2, "shift"), (4, "alt"), (8, "cmd")]
            // Same naming as Record Key, so imported keys read like recorded ones.
            let stroke = KeyboardKeyCatalog.capturedStroke(code: code, characters: nil,
                                                           modifiers: bits.compactMap { mask & $0.0 != 0 ? $0.1 : nil })
            action = .keySequence(keys: [stroke], description: nil)
        default:
            return nil
        }
        guard let action, var encoded = try? Self.function(action) else { return nil }
        // The receiver's factory keyboard descriptors use this known length-1
        // variant. Every other byte must round trip, including consumer usage
        // high bytes and scroll-repeat parameters; unknown data is not guessed.
        if function[0] == 2 && function[1] == 1 { encoded[1] = 1 }
        return encoded == function ? action : nil
    }

    static let media: [SystemAction: UInt8] = [.volumeUp: 0xe9, .volumeDown: 0xea, .mute: 0xe2,
                                              .playPause: 0xcd, .nextTrack: 0xb5, .previousTrack: 0xb6]

    private static func system(_ action: SystemAction) throws -> [UInt8] {
        if let usage = media[action] { return [0x0a, 2, 0, usage, 0, 0, 0] }
        if let shortcut = action.shortcut?.resolve(in: MacSystemShortcut.preferences()) {
            guard !shortcut.flags.contains(.maskSecondaryFn) else { throw unsupported("the Mac Fn key needs the app.") }
            let modifiers: [(CGEventFlags, String)] = [(.maskCommand, "cmd"), (.maskControl, "ctrl"), (.maskShift, "shift"), (.maskAlternate, "alt")]
            return try keyboard(KeyStroke(key: "", modifiers: modifiers.compactMap { shortcut.flags.contains($0.0) ? $0.1 : nil }, keyCode: shortcut.keyCode))
        }
        throw unsupported("this action cannot be stored in the mouse; use a keyboard shortcut.")
    }

    static func keyboard(_ key: KeyStroke) throws -> [UInt8] {
        guard let code = key.keyCode ?? KeyStroke.keyCode(for: key.key), let usage = keyboardUsages[code] else {
            throw unsupported("key has no supported USB HID equivalent.")
        }
        let bits: [String: UInt8] = ["ctrl": 1, "control": 1, "shift": 2, "alt": 4, "option": 4, "cmd": 8, "command": 8]
        var mask: UInt8 = 0
        for name in key.modifiers {
            guard let value = bits[name.lowercased()] else { throw unsupported("modifier \(name) is not supported by the mouse.") }
            mask |= value
        }
        return [2, 2, mask, usage, 0, 0, 0]
    }

    // USB HID keyboard usages paired with Apple's virtual key positions.
    static let keyboardUsages: [UInt16: UInt8] = {
        var result: [UInt16: UInt8] = [:]
        func add(_ codes: [UInt16], startingAt usage: UInt8) {
            for (offset, code) in codes.enumerated() { result[code] = usage + UInt8(offset) }
        }
        add([0,11,8,2,14,3,5,4,34,38,40,37,46,45,31,35,12,15,1,17,32,9,13,7,16,6], startingAt: 4)
        add([18,19,20,21,23,22,26,28,25,29], startingAt: 0x1e)
        add([36,53,51,48,49,27,24,33,30,42], startingAt: 0x28)
        add([41,39,50,43,47,44,57], startingAt: 0x33)
        add([122,120,99,118,96,97,98,100,101,109,103,111], startingAt: 0x3a)
        add([114,115,116,117,119,121,124,123,125,126], startingAt: 0x49)
        add([75,67,78,69,76,83,84,85,86,87,88,89,91,92,82,65], startingAt: 0x54)
        add([105,107,113,106,64,79,80,90], startingAt: 0x68)
        result[10] = 0x64
        result[81] = 0x67
        return result
    }()

    static let keyboardCodes: [UInt8: UInt16] = Dictionary(keyboardUsages.map { ($0.value, $0.key) },
                                                           uniquingKeysWith: { min($0, $1) })
}
