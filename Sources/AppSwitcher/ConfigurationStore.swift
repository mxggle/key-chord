import Foundation

struct ConfigurationStore {
    let fileURL: URL

    init(fileManager: FileManager = .default) throws {
        guard let supportDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        fileURL = supportDirectory
            .appendingPathComponent("AppSwitcher", isDirectory: true)
            .appendingPathComponent("config.json", isDirectory: false)
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func loadOrCreate() throws -> SwitcherConfiguration {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let data = try Self.encoder.encode(Self.defaultConfiguration)
            try data.write(to: fileURL, options: [.atomic])
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        }

        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        guard data.count <= 1_048_576 else {
            throw CocoaError(.fileReadTooLarge)
        }
        let configuration = try Self.decoder.decode(SwitcherConfiguration.self, from: data)
        try ConfigurationValidator.validate(configuration)
        return configuration
    }

    func save(_ configuration: SwitcherConfiguration) throws {
        try ConfigurationValidator.validate(configuration)
        let data = try Self.encoder.encode(configuration)
        guard data.count <= 1_048_576 else {
            throw CocoaError(.fileWriteOutOfSpace)
        }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try data.write(to: fileURL, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        return decoder
    }

    static let defaultConfiguration = SwitcherConfiguration(
        version: 1,
        shortcuts: [
            .init(id: "bridgespace", name: "BridgeSpace", bundleIdentifier: "io.bridgemind.bridgespace", key: "2", modifiers: [.option, .shift], enabled: true, launchIfNeeded: false),
            .init(id: "chatgpt", name: "ChatGPT", bundleIdentifier: "com.openai.chat", key: "q", modifiers: [.option], enabled: true, launchIfNeeded: false),
            .init(id: "chrome", name: "Chrome", bundleIdentifier: "com.google.Chrome", key: "a", modifiers: [.option], enabled: true, launchIfNeeded: true),
            .init(id: "claude", name: "Claude Code", bundleIdentifier: "com.anthropic.claudefordesktop", key: "x", modifiers: [.option], enabled: true, launchIfNeeded: false),
            .init(id: "codex", name: "Codex", bundleIdentifier: "com.openai.codex", key: "c", modifiers: [.option], enabled: true, launchIfNeeded: false),
            .init(id: "cursor", name: "Cursor", bundleIdentifier: "com.todesktop.230313mzl4w4u92", key: "w", modifiers: [.option], enabled: true, launchIfNeeded: false),
            .init(id: "dash", name: "Dash", bundleIdentifier: "com.kapeli.dashdoc", key: "d", modifiers: [.option, .shift], enabled: true, launchIfNeeded: false),
            .init(id: "datagrip", name: "DataGrip", bundleIdentifier: "com.jetbrains.datagrip", key: "d", modifiers: [.option], enabled: true, launchIfNeeded: false),
            .init(id: "finder", name: "Finder", bundleIdentifier: "com.apple.finder", key: "1", modifiers: [.option], enabled: true, launchIfNeeded: true),
            .init(id: "hermes", name: "Hermes", bundleIdentifier: "com.nousresearch.hermes", key: "r", modifiers: [.option], enabled: true, launchIfNeeded: false),
            .init(id: "notion", name: "Notion", bundleIdentifier: "notion.id", key: "e", modifiers: [.option, .shift], enabled: true, launchIfNeeded: false),
            .init(id: "obsidian", name: "Obsidian", bundleIdentifier: "md.obsidian", key: "e", modifiers: [.option], enabled: true, launchIfNeeded: false),
            .init(id: "telegram", name: "Telegram", bundleIdentifier: "ru.keepcoder.Telegram", key: "3", modifiers: [.option], enabled: true, launchIfNeeded: false),
            .init(id: "vscode", name: "VS Code", bundleIdentifier: "com.microsoft.VSCode", key: "z", modifiers: [.option], enabled: true, launchIfNeeded: false),
            .init(id: "warp", name: "Warp", bundleIdentifier: "dev.warp.Warp-Stable", key: "2", modifiers: [.option], enabled: true, launchIfNeeded: false)
        ]
    )
}
