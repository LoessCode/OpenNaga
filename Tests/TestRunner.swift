import Foundation

@main
struct TestRunner {
    static func main() async {
        do {
            let core = try InputEngineTests.run()
            print("Input engine: \(core) checks passed")
            let system = try SystemActionTests.run()
            print("System actions: \(system) checks passed")
            let modifiers = try await ModifierDeliveryTests.run()
            print("Modifier delivery: \(modifiers) checks passed")
            let scroll = try ScrollSensitivityTests.run()
            print("Scroll sensitivity: \(scroll) checks passed")
            let hardware = try HardwareProtocolTests.run()
            print("Hardware protocol: \(hardware) checks passed")
            let onboard = try OnboardProfileTests.run()
            print("Onboard profiles: \(onboard) checks passed")
            let storage = try DataFolderTests.run()
            print("Data folder: \(storage) checks passed")
            let imported = try ImportedProfileTests.run()
            print("Imported profiles: \(imported) checks passed")
            print("PASS: \(core + system + modifiers + scroll + hardware + onboard + storage + imported) checks")
        } catch {
            fputs("FAIL: \(error)\n", stderr)
            exit(1)
        }
    }
}
