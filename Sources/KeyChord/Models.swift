import Carbon
import Foundation

enum AppInfo {
    static let name = "KeyChord"
    static let version = "1.1.1"
    static let buildNumber = "3"
}

enum ShortcutModifier: String, Codable, CaseIterable, Sendable {
    case command
    case control
    case option
    case shift

    var carbonMask: UInt32 {
        switch self {
        case .command: UInt32(cmdKey)
        case .control: UInt32(controlKey)
        case .option: UInt32(optionKey)
        case .shift: UInt32(shiftKey)
        }
    }

    var symbol: String {
        switch self {
        case .command: "⌘"
        case .control: "⌃"
        case .option: "⌥"
        case .shift: "⇧"
        }
    }
}

struct ShortcutDefinition: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var bundleIdentifier: String
    var key: String
    var modifiers: [ShortcutModifier]
    var enabled: Bool
    var launchIfNeeded: Bool
    var hideWhenFrontmost: Bool
    var activateAllWindows: Bool

    init(
        id: String,
        name: String,
        bundleIdentifier: String,
        key: String,
        modifiers: [ShortcutModifier],
        enabled: Bool,
        launchIfNeeded: Bool,
        hideWhenFrontmost: Bool = true,
        activateAllWindows: Bool = true
    ) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.key = key
        self.modifiers = modifiers
        self.enabled = enabled
        self.launchIfNeeded = launchIfNeeded
        self.hideWhenFrontmost = hideWhenFrontmost
        self.activateAllWindows = activateAllWindows
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case bundleIdentifier
        case key
        case modifiers
        case enabled
        case launchIfNeeded
        case hideWhenFrontmost
        case activateAllWindows
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        key = try container.decode(String.self, forKey: .key)
        modifiers = try container.decode([ShortcutModifier].self, forKey: .modifiers)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        launchIfNeeded = try container.decode(Bool.self, forKey: .launchIfNeeded)
        hideWhenFrontmost = try container.decodeIfPresent(
            Bool.self,
            forKey: .hideWhenFrontmost
        ) ?? true
        activateAllWindows = try container.decodeIfPresent(
            Bool.self,
            forKey: .activateAllWindows
        ) ?? true
    }

    var carbonModifiers: UInt32 {
        modifiers.reduce(0) { $0 | $1.carbonMask }
    }

    var displayShortcut: String {
        let order: [ShortcutModifier] = [.control, .option, .shift, .command]
        let symbols = order.filter(modifiers.contains).map(\.symbol).joined()
        return symbols + key.uppercased()
    }

    func usesHotKey(
        key candidateKey: String,
        modifiers candidateModifiers: [ShortcutModifier]
    ) -> Bool {
        !key.isEmpty
            && key.caseInsensitiveCompare(candidateKey) == .orderedSame
            && carbonModifiers == candidateModifiers.reduce(0) { $0 | $1.carbonMask }
    }
}

struct GeneralSettings: Codable, Equatable, Sendable {
    var showDockIcon: Bool
    var showMenuBarIcon: Bool
    var showShortcutsInMenu: Bool

    static let defaults = GeneralSettings(
        showDockIcon: true,
        showMenuBarIcon: true,
        showShortcutsInMenu: true
    )

    private enum CodingKeys: String, CodingKey {
        case showDockIcon
        case showMenuBarIcon
        case showShortcutsInMenu
    }

    init(
        showDockIcon: Bool,
        showMenuBarIcon: Bool = true,
        showShortcutsInMenu: Bool
    ) {
        self.showDockIcon = showDockIcon
        self.showMenuBarIcon = showMenuBarIcon
        self.showShortcutsInMenu = showShortcutsInMenu
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showDockIcon = try container.decodeIfPresent(
            Bool.self,
            forKey: .showDockIcon
        ) ?? true
        showMenuBarIcon = try container.decodeIfPresent(
            Bool.self,
            forKey: .showMenuBarIcon
        ) ?? true
        showShortcutsInMenu = try container.decodeIfPresent(
            Bool.self,
            forKey: .showShortcutsInMenu
        ) ?? true
    }
}

struct SwitcherConfiguration: Codable, Equatable, Sendable {
    var version: Int
    var shortcuts: [ShortcutDefinition]
    var settings: GeneralSettings

    init(
        version: Int,
        shortcuts: [ShortcutDefinition],
        settings: GeneralSettings = .defaults
    ) {
        self.version = version
        self.shortcuts = shortcuts
        self.settings = settings
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case shortcuts
        case settings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        shortcuts = try container.decode([ShortcutDefinition].self, forKey: .shortcuts)
        settings = try container.decodeIfPresent(
            GeneralSettings.self,
            forKey: .settings
        ) ?? .defaults
    }

    func shortcutUsing(
        key: String,
        modifiers: [ShortcutModifier],
        excludingID: String
    ) -> ShortcutDefinition? {
        shortcuts.first {
            $0.id != excludingID && $0.usesHotKey(key: key, modifiers: modifiers)
        }
    }
}

enum KeyCodeResolver {
    private static let keyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5,
        "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
        "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
        "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "return": 36, "l": 37, "j": 38, "'": 39, "k": 40,
        ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46,
        ".": 47, "tab": 48, "space": 49, "`": 50, "delete": 51,
        "escape": 53, "f17": 64, "f18": 79, "f19": 80, "f20": 90,
        "f5": 96, "f6": 97, "f7": 98, "f3": 99, "f8": 100,
        "f9": 101, "f11": 103, "f13": 105, "f16": 106, "f14": 107,
        "f10": 109, "f12": 111, "f15": 113, "home": 115,
        "pageup": 116, "forwarddelete": 117, "f4": 118, "end": 119,
        "f2": 120, "pagedown": 121, "f1": 122, "left": 123,
        "right": 124, "down": 125, "up": 126
    ]

    static func resolve(_ key: String) -> UInt32? {
        keyCodes[key.lowercased()]
    }

    static func key(for keyCode: UInt32) -> String? {
        keyCodes.first(where: { $0.value == keyCode })?.key
    }
}

enum ConfigurationError: LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case tooManyShortcuts(Int)
    case invalidIdentifier(String)
    case duplicateIdentifier(String)
    case invalidName(String)
    case invalidBundleIdentifier(String)
    case missingHotKey(String)
    case unknownKey(String)
    case noModifiers(String)
    case duplicateHotKey(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            "Unsupported configuration version: \(version)."
        case .tooManyShortcuts(let count):
            "Configuration contains \(count) shortcuts; the maximum is 100."
        case .invalidIdentifier(let id):
            "Invalid shortcut identifier: \(id)."
        case .duplicateIdentifier(let id):
            "Duplicate shortcut identifier: \(id)."
        case .invalidName(let name):
            "Invalid shortcut name: \(name)."
        case .invalidBundleIdentifier(let identifier):
            "Invalid bundle identifier: \(identifier)."
        case .missingHotKey(let name):
            "Set a keyboard shortcut for \(name) before enabling it."
        case .unknownKey(let key):
            "Unknown key: \(key)."
        case .noModifiers(let name):
            "Shortcut \(name) must use at least one modifier."
        case .duplicateHotKey(let shortcut):
            "Duplicate hot key: \(shortcut)."
        }
    }
}

enum ConfigurationValidator {
    private static let safeIdentifier = try! NSRegularExpression(
        pattern: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"#
    )
    private static let safeBundleIdentifier = try! NSRegularExpression(
        pattern: #"^[A-Za-z0-9][A-Za-z0-9.-]{0,254}$"#
    )

    static func validate(_ configuration: SwitcherConfiguration) throws {
        guard configuration.version == 1 else {
            throw ConfigurationError.unsupportedVersion(configuration.version)
        }
        guard configuration.shortcuts.count <= 100 else {
            throw ConfigurationError.tooManyShortcuts(configuration.shortcuts.count)
        }

        var identifiers = Set<String>()
        var hotKeys = Set<String>()

        for shortcut in configuration.shortcuts {
            guard matches(shortcut.id, expression: safeIdentifier) else {
                throw ConfigurationError.invalidIdentifier(shortcut.id)
            }
            guard identifiers.insert(shortcut.id).inserted else {
                throw ConfigurationError.duplicateIdentifier(shortcut.id)
            }
            let containsControlCharacter = shortcut.name.unicodeScalars.contains {
                CharacterSet.controlCharacters.contains($0)
            }
            guard !shortcut.name.isEmpty, shortcut.name.count <= 80,
                  !containsControlCharacter else {
                throw ConfigurationError.invalidName(shortcut.name)
            }
            guard matches(shortcut.bundleIdentifier, expression: safeBundleIdentifier) else {
                throw ConfigurationError.invalidBundleIdentifier(shortcut.bundleIdentifier)
            }
            if shortcut.key.isEmpty || shortcut.modifiers.isEmpty {
                guard !shortcut.enabled else {
                    throw ConfigurationError.missingHotKey(shortcut.name)
                }
                continue
            }
            guard KeyCodeResolver.resolve(shortcut.key) != nil else {
                throw ConfigurationError.unknownKey(shortcut.key)
            }

            let hotKey = "\(shortcut.carbonModifiers):\(shortcut.key.lowercased())"
            if shortcut.enabled, !hotKeys.insert(hotKey).inserted {
                throw ConfigurationError.duplicateHotKey(shortcut.displayShortcut)
            }
        }
    }

    private static func matches(_ value: String, expression: NSRegularExpression) -> Bool {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.firstMatch(in: value, range: range)?.range == range
    }
}
