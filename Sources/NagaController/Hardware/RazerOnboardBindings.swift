import Foundation

// Wire facts from OpenRazer issue 2845 and OpenSnek USB_PROFILE_CRUD_SPEC.md.
// Independently verified on receiver 1532:00b4 on 2026-09-11. No foreign code copied.
// Profile 0 is the active view; profile 1 is the stored bank. Neither is changed here.
struct RazerOnboardBinding: Equatable, Codable {
    let bytes: [UInt8]
    var profile: UInt8 { bytes[0] }
    var buttonID: UInt8 { bytes[1] }

    init(bytes: [UInt8], profile: UInt8, buttonID: UInt8) throws {
        guard bytes.count == 10, bytes[0] == profile, bytes[1] == buttonID else {
            throw RazerHardwareError.malformed("Invalid hardware assignment or one that refers to another button.")
        }
        // Preserve every function byte, including unknown types. Factory keyboard
        // bindings use length 1 but still carry a usage in byte 6 on this receiver.
        // Byte 2 selects the layer in requests (0 normal, 1 Hypershift). Replies do
        // not echo it: a Synapse-configured mouse reports 01 on some controls in
        // both layers. Store 0 and pass the layer separately; keeping the reply
        // value would send a restore to the wrong layer.
        var normalized = bytes
        normalized[2] = 0
        self.bytes = normalized
    }
}

enum RazerOnboardBindings {
    static let getButtonIDs = RazerCommand(transaction: 0x1f, commandClass: 2, id: 0x84,
                                         arguments: Array(repeating: 0, count: 22))

    static func readCommand(profile: UInt8, buttonID: UInt8, layer: UInt8 = 0) throws -> RazerCommand {
        guard profile <= 1, layer <= 1 else {
            throw RazerHardwareError.invalidValue("Only the active and stored profiles and two layers are supported.")
        }
        return RazerCommand(transaction: 0x1f, commandClass: 2, id: 0x8c,
                            arguments: [profile, buttonID, layer, 0, 0, 0, 0, 0, 0, 0])
    }

    static func writeCommand(_ binding: RazerOnboardBinding, layer: UInt8) throws -> RazerCommand {
        guard layer <= 1 else { throw RazerHardwareError.invalidValue("Unknown assignment layer.") }
        var arguments = binding.bytes
        arguments[2] = layer
        return RazerCommand(transaction: 0x1f, commandClass: 2, id: 0x0c, arguments: arguments)
    }

    static func decodeButtonIDs(_ bytes: [UInt8]) throws -> [UInt8] {
        guard bytes.count == 22, let count = bytes.first, count > 0, Int(count) < bytes.count else {
            throw RazerHardwareError.malformed("Invalid hardware button list.")
        }
        let ids = Array(bytes[1...Int(count)])
        guard !ids.contains(0), Set(ids).count == ids.count else {
            throw RazerHardwareError.malformed("Duplicate or incomplete hardware button list.")
        }
        return ids
    }

    static func read(session: RazerHardwareSession, profile: UInt8, layer: UInt8 = 0) throws -> [RazerOnboardBinding] {
        // Validate the bank before any USB traffic.
        _ = try readCommand(profile: profile, buttonID: 1, layer: layer)
        let ids = try decodeButtonIDs(session.execute(getButtonIDs))
        return try ids.map { id in
            let bytes = try session.execute(readCommand(profile: profile, buttonID: id, layer: layer))
            return try RazerOnboardBinding(bytes: bytes, profile: profile, buttonID: id)
        }
    }

    // Read-only view for importing into a local profile: button ID to its seven
    // function bytes. Use the same identity validation and reply normalization
    // as backup and restore, retaining unknown function bytes unchanged.
    static func readFunctions(session: RazerHardwareSession, profile: UInt8, layer: UInt8 = 0) throws -> [UInt8: [UInt8]] {
        let bindings = try read(session: session, profile: profile, layer: layer)
        let expected = Set(OnboardProfilePlan.buttonIDs.values).union([UInt8(9), UInt8(10)])
        guard Set(bindings.map(\.buttonID)) == expected else {
            throw RazerHardwareError.malformed("Incomplete or unexpected mouse button layout.")
        }
        return Dictionary(uniqueKeysWithValues: bindings.map { ($0.buttonID, Array($0.bytes.dropFirst(3))) })
    }
}
