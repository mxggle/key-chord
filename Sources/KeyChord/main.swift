import AppKit
import Foundation

@MainActor
private func runCommandLineMode(arguments: [String]) -> Int32? {
    guard arguments.count > 1 else {
        return nil
    }

    switch arguments[1] {
    case "--show-settings", "--diagnose-status-item", "--trace-status-item":
        return nil

    case "--version", "-v":
        FileHandle.standardOutput.write(Data("\(AppInfo.name) v\(AppInfo.version) (build \(AppInfo.buildNumber))\n".utf8))
        return 0

    case "--probe-hotkeys":
        do {
            let configuration = try ConfigurationStore().loadOrCreate()
            let manager = HotKeyManager()
            let registrations = manager.register(configuration.shortcuts)
            defer { manager.unregisterAll() }
            for registration in registrations {
                if let error = registration.error {
                    print("CONFLICT \(registration.shortcut.displayShortcut) \(registration.shortcut.name) OSStatus=\(error)")
                } else {
                    print("OK \(registration.shortcut.displayShortcut) \(registration.shortcut.name)")
                }
            }
            return registrations.contains(where: { $0.error != nil }) ? 1 : 0
        } catch {
            FileHandle.standardError.write(Data("Hot-key probe failed: \(error.localizedDescription)\n".utf8))
            return 1
        }

    case "--self-test":
        let failures = SelfTest.run()
        if failures.isEmpty {
            FileHandle.standardOutput.write(Data("All self-tests passed.\n".utf8))
            return 0
        }
        for failure in failures {
            FileHandle.standardError.write(Data("FAIL: \(failure)\n".utf8))
        }
        return 1

    case "--print-default-config":
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            let data = try encoder.encode(ConfigurationStore.defaultConfiguration)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
            return 0
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            return 1
        }

    case "--validate-config":
        guard arguments.count == 3 else {
            FileHandle.standardError.write(Data("Usage: KeyChord --validate-config PATH\n".utf8))
            return 2
        }
        do {
            let store = ConfigurationStore(fileURL: URL(fileURLWithPath: arguments[2]))
            _ = try store.loadOrCreate()
            FileHandle.standardOutput.write(Data("Configuration is valid.\n".utf8))
            return 0
        } catch {
            FileHandle.standardError.write(Data("Invalid configuration: \(error.localizedDescription)\n".utf8))
            return 1
        }

    default:
        FileHandle.standardError.write(Data("Unknown option: \(arguments[1])\n".utf8))
        return 2
    }
}

if let exitCode = runCommandLineMode(arguments: CommandLine.arguments) {
    exit(exitCode)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
