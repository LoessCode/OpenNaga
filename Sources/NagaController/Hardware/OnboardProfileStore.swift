import Foundation

// Invoked only by explicit save/restore operations on the hardware worker queue.
enum OnboardProfileStore {
    struct State: Codable {
        let identity: String
        let original: [[UInt8]]
        var name: String
        var pending: Bool
        // Hypershift layer backup, captured before OpenNaga first writes that
        // layer. Absent in journals written before 2.6.0 and for profiles that
        // never used Hypershift.
        var originalHypershift: [[UInt8]]? = nil
    }
    static var url: URL { DataFolder.file("onboard-profile.json") }
    // A pending or unreadable journal also blocks software interception after a crash.
    static var isActive: Bool { FileManager.default.fileExists(atPath: url.path) }
    static var savedName: String? {
        guard let state = try? load(from: url), !state.pending else { return nil }
        return state.name
    }

    // The backup holds this model's original assignments, so it follows the
    // receiver model (vendor:product) rather than the USB port it was saved on.
    static func sameReceiver(_ a: String, _ b: String) -> Bool {
        a.split(separator: ":").prefix(2) == b.split(separator: ":").prefix(2)
    }

    static func load(from url: URL) throws -> State {
        let state = try JSONDecoder().decode(State.self, from: Data(contentsOf: url))
        guard !state.identity.isEmpty else { throw RazerHardwareError.malformed("Incomplete mouse backup.") }
        let original = try validated(state.original)
        let hypershift = try state.originalHypershift.map(validated)
        guard hypershift.map({ Set($0.map { $0[1] }) == Set(original.map { $0[1] }) }) ?? true else {
            throw RazerHardwareError.malformed("The Hypershift backup does not match the mouse controls.")
        }
        return State(identity: state.identity, original: original, name: state.name, pending: state.pending,
                     originalHypershift: hypershift)
    }

    private static func validated(_ layer: [[UInt8]]) throws -> [[UInt8]] {
        guard layer.count == 21 else { throw RazerHardwareError.malformed("Incomplete mouse backup.") }
        var ids = Set<UInt8>()
        return try layer.map { bytes in
            guard bytes.count == 10 else { throw RazerHardwareError.malformed("Invalid mouse backup.") }
            guard ids.insert(bytes[1]).inserted else { throw RazerHardwareError.malformed("Duplicate button in the backup.") }
            return try RazerOnboardBinding(bytes: bytes, profile: 1, buttonID: bytes[1]).bytes
        }
    }

    private struct Write {
        let bytes: [UInt8]
        let layer: UInt8
        let previous: [UInt8]?
    }

    static func save(_ plan: OnboardProfilePlan, session: RazerHardwareSession, identity: String, at url: URL = url) throws {
        guard plan.isSupported else { throw RazerHardwareError.invalidValue(plan.issues.joined(separator: "\n")) }
        guard try session.readMode() == 0 else { throw RazerHardwareError.invalidValue("Turn off driver mode before saving to the mouse.") }
        let previousData = FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
        let previous = previousData == nil ? nil : try load(from: url)
        guard previous.map({ sameReceiver($0.identity, identity) && !$0.pending }) ?? true else {
            throw RazerHardwareError.invalidValue("Restore the pending backup with the original receiver first.")
        }
        let before = try RazerOnboardBindings.read(session: session, profile: 1).map(\.bytes)
        guard before.count == 21 else { throw RazerHardwareError.malformed("Unexpected button layout.") }
        let original = previous?.original ?? before
        guard Set(original.map { $0[1] }) == Set(before.map { $0[1] }),
              Set(plan.functions.keys).isSubset(of: Set(before.map { $0[1] })) else {
            throw RazerHardwareError.malformed("The backup or profile does not match the mouse buttons.")
        }
        let targets = original.map { bytes -> [UInt8] in
            guard let function = plan.functions[bytes[1]] else { return bytes }
            return [1, bytes[1], 0] + function
        }
        // The Hypershift layer is read and written only when this save uses it
        // or an earlier save changed it. Otherwise it is never touched.
        var originalHypershift = previous?.originalHypershift
        var hypershiftBefore: [[UInt8]] = []
        var hypershiftTargets: [[UInt8]] = []
        if plan.hasHypershiftKey || originalHypershift != nil {
            hypershiftBefore = try RazerOnboardBindings.read(session: session, profile: 1, layer: 1).map(\.bytes)
            guard Set(hypershiftBefore.map { $0[1] }) == Set(before.map { $0[1] }),
                  Set(plan.hypershiftFunctions.keys).isSubset(of: Set(before.map { $0[1] })) else {
                throw RazerHardwareError.malformed("The Hypershift layer does not match the mouse buttons.")
            }
            originalHypershift = originalHypershift ?? hypershiftBefore
            if plan.hasHypershiftKey {
                // Controls without a Hypershift action keep their standard function.
                hypershiftTargets = targets.map { target in
                    plan.hypershiftFunctions[target[1]].map { [1, target[1], 0] + $0 } ?? target
                }
            } else {
                hypershiftTargets = originalHypershift ?? []
            }
        }
        let beforeByID = Dictionary(uniqueKeysWithValues: before.map { ($0[1], $0) })
        let hypershiftBeforeByID = Dictionary(uniqueKeysWithValues: hypershiftBefore.map { ($0[1], $0) })
        // A Hypershift layer write sets reply byte 2 to 01 on that control, and a
        // later normal-layer write clears it (observed on 1532:00b4, 2026-10-21).
        // Write the Hypershift layer first, then the normal layer of every
        // control touched in either layer, so the flag returns to 00.
        let hypershiftChanged = hypershiftTargets.filter { hypershiftBeforeByID[$0[1]] != $0 }
        let shiftedIDs = Set(hypershiftChanged.map { $0[1] })
        let changed = hypershiftChanged.map { Write(bytes: $0, layer: 1, previous: hypershiftBeforeByID[$0[1]]) }
            + targets.filter { beforeByID[$0[1]] != $0 || shiftedIDs.contains($0[1]) }
                .map { Write(bytes: $0, layer: 0, previous: beforeByID[$0[1]]) }
        var state = State(identity: previous?.identity ?? identity, original: original, name: plan.name, pending: true,
                          originalHypershift: originalHypershift)
        try persist(state, at: url)
        do {
            for change in changed { try write(change.bytes, layer: change.layer, session: session) }
            // Also verify the active mirror, including an unchanged saved profile.
            for target in targets { try verify(target, profile: 0, session: session) }
            for target in hypershiftTargets { try verify(target, profile: 0, layer: 1, session: session) }
            state.pending = false
            try persist(state, at: url)
        } catch {
            let failure = error
            do {
                // Include the uncertain write: an ACK timeout can follow a successful SET.
                for change in changed.reversed() {
                    if let old = change.previous { try write(old, layer: change.layer, session: session) }
                }
                if let previousData { try previousData.write(to: url, options: .atomic) }
                else { try FileManager.default.removeItem(at: url) }
            } catch {
                throw RazerHardwareError.transport("Save interrupted. The backup was kept; use Restore Previous Assignments. \(error.localizedDescription)")
            }
            throw failure
        }
    }

    static func restore(session: RazerHardwareSession, identity: String, at url: URL = url) throws {
        var state = try load(from: url)
        guard sameReceiver(state.identity, identity) else { throw RazerHardwareError.invalidValue("Connect the receiver that was used for the save.") }
        guard try session.readMode() == 0 else { throw RazerHardwareError.invalidValue("Turn off driver mode before restoring.") }
        let current = try RazerOnboardBindings.read(session: session, profile: 1).map(\.bytes)
        guard Set(current.map { $0[1] }) == Set(state.original.map { $0[1] }) else {
            throw RazerHardwareError.malformed("The backup does not match the mouse controls.")
        }
        state.pending = true
        try persist(state, at: url)
        let currentByID = Dictionary(uniqueKeysWithValues: current.map { ($0[1], $0) })
        // Hypershift layer first; its controls then get a normal-layer write
        // that clears the reply flag (see save).
        var shiftedIDs = Set<UInt8>()
        if let hypershift = state.originalHypershift {
            let currentHypershift = try RazerOnboardBindings.read(session: session, profile: 1, layer: 1).map(\.bytes)
            let currentHypershiftByID = Dictionary(uniqueKeysWithValues: currentHypershift.map { ($0[1], $0) })
            for original in hypershift {
                if currentHypershiftByID[original[1]] != original {
                    try write(original, layer: 1, session: session)
                    shiftedIDs.insert(original[1])
                }
                try verify(original, profile: 0, layer: 1, session: session)
            }
        }
        for original in state.original {
            if currentByID[original[1]] != original || shiftedIDs.contains(original[1]) { try write(original, session: session) }
            try verify(original, profile: 0, session: session)
        }
        try FileManager.default.removeItem(at: url)
    }

    private static func persist(_ state: State, at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
    }

    static func write(_ bytes: [UInt8], layer: UInt8 = 0, session: RazerHardwareSession) throws {
        guard bytes.count == 10 else { throw RazerHardwareError.invalidValue("Invalid assignment to write.") }
        // Normalized bytes; the layer is set explicitly in the request.
        let binding = try RazerOnboardBinding(bytes: bytes, profile: 1, buttonID: bytes[1])
        _ = try session.execute(RazerOnboardBindings.writeCommand(binding, layer: layer))
        try verify(binding.bytes, profile: 1, layer: layer, session: session)
    }

    private static func verify(_ bytes: [UInt8], profile: UInt8, layer: UInt8 = 0, session: RazerHardwareSession) throws {
        var expected = bytes
        expected[0] = profile
        let actual = try session.execute(RazerOnboardBindings.readCommand(profile: profile, buttonID: bytes[1], layer: layer))
        // Compare as normalized bindings: reply byte 2 is a status, not the layer.
        guard let binding = try? RazerOnboardBinding(bytes: actual, profile: profile, buttonID: bytes[1]),
              binding.bytes == expected else { throw RazerHardwareError.readback }
    }
}
