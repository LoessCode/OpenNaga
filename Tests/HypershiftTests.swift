import Cocoa

enum HypershiftTests {
    struct Failure: Error, CustomStringConvertible { let description: String }

    static func run() throws -> Int {
        var count = 0
        func check(_ condition: Bool, _ label: String) throws {
            guard condition else { throw Failure(description: label) }
            count += 1
        }
        try runtime(check)
        try persistence(check)
        return count
    }

    private static func key(_ name: String, _ code: UInt16) -> ActionType {
        .keySequence(keys: [KeyStroke(key: name, modifiers: [], keyCode: code)], description: nil)
    }

    private static func runtime(_ check: (Bool, String) throws -> Void) throws {
        var events: [CGEvent] = []
        let mapper = ButtonMapper(eventSink: { events.append($0) })
        mapper.modifierKeyState = { _ in false }
        func downs() -> [Int64] {
            defer { events.removeAll() }
            return events.filter { $0.type == .keyDown }.map { $0.getIntegerValueField(.keyboardEventKeycode) }
        }
        func tap(_ button: Int) { mapper.handlePress(buttonIndex: button); mapper.handleRelease(buttonIndex: button) }
        let a: Int64 = 0, b: Int64 = 11
        mapper.updateMapping([12: .hypershift(description: nil), 11: .hypershift(description: nil),
                              1: key("a", 0), 2: key("a", 0)],
                             hypershift: [1: key("b", 11), 3: key("b", 11), 12: key("b", 11),
                                          4: .mouse(action: .dpiUp, description: nil),
                                          5: .hypershift(description: nil)])
        try check(mapper.hasMapping(buttonIndex: 12) && !mapper.isHypershiftActive, "A Hypershift control is a consumed mapping that starts inactive")
        try check(!mapper.hasMapping(buttonIndex: 3), "A control mapped only in the Hypershift layer passes through normally")
        tap(1)
        try check(downs() == [a], "The standard layer is used while Hypershift is not held")

        mapper.handlePress(buttonIndex: 12)
        try check(mapper.isHypershiftActive && events.isEmpty, "Holding the Hypershift control activates the layer without output")
        try check(mapper.hasMapping(buttonIndex: 3), "A Hypershift-only control is consumed while the layer is held")
        try check(!mapper.hasMapping(buttonIndex: 4), "Hardware DPI functions never run in the software Hypershift layer")
        try check(!mapper.hasMapping(buttonIndex: 5), "The Hypershift layer cannot contain another Hypershift control")
        tap(1)
        try check(downs() == [b], "A Hypershift assignment replaces the standard action while held")
        tap(2)
        try check(downs() == [a], "Controls without a Hypershift assignment keep their standard action")
        mapper.handlePress(buttonIndex: 12)
        try check(mapper.isHypershiftActive && events.isEmpty, "A repeated Hypershift press keeps the control a Hypershift key")
        mapper.handleRelease(buttonIndex: 12)
        try check(!mapper.isHypershiftActive, "Releasing the Hypershift control leaves the layer")
        tap(1)
        try check(downs() == [a], "The standard layer returns after release")

        // An output started in the Hypershift layer must end with its own key.
        mapper.handlePress(buttonIndex: 12)
        mapper.handlePress(buttonIndex: 1)
        mapper.handleRelease(buttonIndex: 12)
        mapper.handleRelease(buttonIndex: 1)
        let ups = events.filter { $0.type == .keyUp }.map { $0.getIntegerValueField(.keyboardEventKeycode) }
        try check(downs() == [b] && ups == [b], "A held Hypershift output releases the same key after the layer ends")

        mapper.handlePress(buttonIndex: 11)
        mapper.handlePress(buttonIndex: 12)
        mapper.handleRelease(buttonIndex: 11)
        try check(mapper.isHypershiftActive, "The layer stays active while another Hypershift control is held")
        mapper.handleRelease(buttonIndex: 12)
        try check(!mapper.isHypershiftActive, "The layer ends when every Hypershift control is released")

        mapper.handlePress(buttonIndex: 12)
        mapper.releaseAll()
        try check(!mapper.isHypershiftActive, "Resetting input state also leaves the Hypershift layer")
        mapper.handlePress(buttonIndex: 12)
        mapper.updateMapping([1: key("a", 0)], hypershift: [1: key("b", 11)])
        tap(1)
        try check(!mapper.isHypershiftActive && downs() == [a], "A profile change drops a held Hypershift state")
    }

    private static func persistence(_ check: (Bool, String) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let domain = "OpenNaga.HypershiftTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: domain)
        }
        let url = root.appendingPathComponent("profiles.json")
        let config = ConfigManager(storageURL: url, defaults: defaults)
        try check(config.createProfile(name: "Layers"), "A profile for the Hypershift layer can be created")
        config.setAction(forButton: 12, action: .hypershift(description: "Shift"))
        config.setAction(forButton: 1, action: key("b", 11), layer: .hypershift)
        config.setAction(forButton: 2, action: .hypershift(description: nil), layer: .hypershift)
        try check(config.mappingForCurrentProfile()[12] == .hypershift(description: "Shift"), "The Hypershift key is a standard-layer action")
        try check(config.mappingForCurrentProfile()[1] == nil, "A Hypershift assignment does not change the standard layer")
        try check(config.mappingForCurrentProfile(layer: .hypershift) == [1: key("b", 11)], "The Hypershift layer stores its own assignments only")

        try check(ButtonMapper.shared.hasMapping(buttonIndex: 12) && !ButtonMapper.shared.hasMapping(buttonIndex: 1), "The runtime mapper receives the standard layer")
        ButtonMapper.shared.handlePress(buttonIndex: 12)
        let shifted = ButtonMapper.shared.hasMapping(buttonIndex: 1)
        ButtonMapper.shared.handleRelease(buttonIndex: 12)
        try check(shifted && !ButtonMapper.shared.hasMapping(buttonIndex: 1), "The runtime mapper receives the Hypershift layer")

        let loaded = ConfigManager(storageURL: url, defaults: defaults)
        loaded.load()
        try check(loaded.currentProfileName == "Layers" && loaded.mappingForCurrentProfile(layer: .hypershift)[1] == key("b", 11), "The Hypershift layer survives a restart")

        loaded.setAction(forButton: 3, action: .profileSwitch(profile: "Layers", description: nil), layer: .hypershift)
        try check(loaded.renameProfile(from: "Layers", to: "Renamed"), "A profile with a Hypershift layer can be renamed")
        try check(loaded.mappingForCurrentProfile(layer: .hypershift)[3] == .profileSwitch(profile: "Renamed", description: nil), "Renaming updates profile switches in the Hypershift layer")
        try check(loaded.duplicateProfile(source: "Renamed", as: "Copy") && loaded.mappingForCurrentProfile(layer: .hypershift)[1] == key("b", 11), "Duplicating a profile copies its Hypershift layer")

        let exported = root.appendingPathComponent("export.json")
        try loaded.exportCurrentProfile(to: exported)
        let file = try JSONDecoder().decode(ProfilesFile.self, from: Data(contentsOf: exported))
        try check(file.profiles["Copy"]?.hypershift?["1"]?.type == "keySequence" && file.profiles["Copy"]?.buttons["12"]?.type == "hypershift", "Export retains both layers")

        loaded.setAction(forButton: 1, action: nil, layer: .hypershift)
        loaded.setAction(forButton: 3, action: nil, layer: .hypershift)
        try check(loaded.profiles["Copy"]?.hypershift == nil, "An empty Hypershift layer is removed from the profile file")
        let legacy = Data("{\"buttons\":{}}".utf8)
        try check(JSONDecoder().decode(Profile.self, from: legacy).hypershift == nil, "Profiles written before the Hypershift layer need no migration")
        try check(OnboardProfilePlan(name: "Layers", mapping: [12: .hypershift(description: nil)]).isSupported, "Mouse memory stores a Hypershift key")
        ButtonMapper.shared.updateMapping([:])
    }
}
