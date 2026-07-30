import AppKit
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var configuration: SwitcherConfiguration
    @Published var searchText = ""
    @Published var selectedSection: SettingsSection? = .shortcuts
    @Published private(set) var feedbackMessage: String?
    @Published private(set) var feedbackIsError = false
    @Published private(set) var launchAtLoginEnabled: Bool
    @Published private(set) var registrationIssues: [String: String] = [:]

    private let store: ConfigurationStore
    private let onApply: (SwitcherConfiguration) -> Void
    private var persistedConfiguration: SwitcherConfiguration
    private var feedbackSequence = 0

    init(
        configuration: SwitcherConfiguration,
        store: ConfigurationStore,
        onApply: @escaping (SwitcherConfiguration) -> Void
    ) {
        self.configuration = configuration
        persistedConfiguration = configuration
        self.store = store
        self.onApply = onApply
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    var isDirty: Bool {
        configuration != persistedConfiguration
    }

    var validationMessage: String? {
        do {
            try ConfigurationValidator.validate(configuration)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    var filteredShortcuts: [ShortcutDefinition] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return configuration.shortcuts
        }
        return configuration.shortcuts.filter { shortcut in
            shortcut.name.localizedCaseInsensitiveContains(query)
                || shortcut.bundleIdentifier.localizedCaseInsensitiveContains(query)
                || shortcut.displayShortcut.localizedCaseInsensitiveContains(query)
        }
    }

    struct ShortcutConflict: Identifiable, Equatable {
        let sourceID: String
        let sourceName: String
        let targetID: String
        let targetName: String
        let key: String
        let modifiers: [ShortcutModifier]

        var id: String {
            "\(sourceID):\(targetID):\(key):\(modifiers.map(\.rawValue).joined(separator: ","))"
        }

        var displayShortcut: String {
            ShortcutDefinition(
                id: "preview",
                name: "Preview",
                bundleIdentifier: "com.example.preview",
                key: key,
                modifiers: modifiers,
                enabled: false,
                launchIfNeeded: false
            ).displayShortcut
        }
    }

    func binding(forShortcutID id: String) -> Binding<ShortcutDefinition>? {
        guard let index = configuration.shortcuts.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        return Binding(
            get: { self.configuration.shortcuts[index] },
            set: { self.configuration.shortcuts[index] = $0 }
        )
    }

    /// Applies an available shortcut immediately, or returns a conflict that
    /// the view can present before moving the shortcut away from another app.
    func assignShortcut(
        to targetID: String,
        key: String,
        modifiers: [ShortcutModifier]
    ) -> ShortcutConflict? {
        guard let targetIndex = configuration.shortcuts.firstIndex(where: {
            $0.id == targetID
        }) else {
            return nil
        }

        if key.isEmpty || modifiers.isEmpty {
            configuration.shortcuts[targetIndex].key = ""
            configuration.shortcuts[targetIndex].modifiers = []
            configuration.shortcuts[targetIndex].enabled = false
            return nil
        }

        if let source = configuration.shortcutUsing(
            key: key,
            modifiers: modifiers,
            excludingID: targetID
        ) {
            return ShortcutConflict(
                sourceID: source.id,
                sourceName: source.name,
                targetID: targetID,
                targetName: configuration.shortcuts[targetIndex].name,
                key: key,
                modifiers: modifiers
            )
        }

        configuration.shortcuts[targetIndex].key = key
        configuration.shortcuts[targetIndex].modifiers = modifiers
        return nil
    }

    func moveShortcut(_ conflict: ShortcutConflict) {
        guard let sourceIndex = configuration.shortcuts.firstIndex(where: {
            $0.id == conflict.sourceID
        }),
        let targetIndex = configuration.shortcuts.firstIndex(where: {
            $0.id == conflict.targetID
        }),
        configuration.shortcuts[sourceIndex].usesHotKey(
            key: conflict.key,
            modifiers: conflict.modifiers
        ) else {
            setFeedback(
                "The shortcut changed before it could be moved. Please record it again.",
                isError: true
            )
            return
        }

        configuration.shortcuts[sourceIndex].key = ""
        configuration.shortcuts[sourceIndex].modifiers = []
        configuration.shortcuts[sourceIndex].enabled = false
        configuration.shortcuts[targetIndex].key = conflict.key
        configuration.shortcuts[targetIndex].modifiers = conflict.modifiers
        configuration.shortcuts[targetIndex].enabled = true
        setFeedback(
            "\(conflict.displayShortcut) moved from \(conflict.sourceName) to \(conflict.targetName). Save to apply."
        )
    }

    func save() {
        do {
            try store.save(configuration)
            persistedConfiguration = configuration
            setFeedback("Changes saved and shortcuts reloaded.")
            onApply(configuration)
        } catch {
            setFeedback(error.localizedDescription, isError: true)
        }
    }

    func revert() {
        configuration = persistedConfiguration
        setFeedback("Unsaved changes were discarded.")
    }

    func replacePersistedConfiguration(_ newConfiguration: SwitcherConfiguration) {
        guard !isDirty else { return }
        configuration = newConfiguration
        persistedConfiguration = newConfiguration
        setFeedback(nil)
    }

    func resetToDefaults() {
        configuration = ConfigurationStore.defaultConfiguration
        setFeedback("Defaults restored. Save to apply them.")
    }

    func addApplication() {
        let panel = NSOpenPanel()
        panel.title = "Choose an application"
        panel.prompt = "Add Application"
        panel.message = "Select the application you want to activate with a shortcut."
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.resolvesAliases = true

        guard panel.runModal() == .OK, let applicationURL = panel.url else {
            return
        }
        guard applicationURL.pathExtension.lowercased() == "app",
              let bundle = Bundle(url: applicationURL),
              let bundleIdentifier = bundle.bundleIdentifier,
              !bundleIdentifier.isEmpty else {
            setFeedback("The selected item is not a valid macOS application.", isError: true)
            return
        }
        guard !configuration.shortcuts.contains(where: {
            $0.bundleIdentifier == bundleIdentifier
        }) else {
            setFeedback("That application already has a shortcut.", isError: true)
            return
        }

        let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? applicationURL.deletingPathExtension().lastPathComponent
        let baseID = slug(displayName)
        var identifier = baseID
        var suffix = 2
        let existingIDs = Set(configuration.shortcuts.map(\.id))
        while existingIDs.contains(identifier) {
            identifier = "\(baseID)-\(suffix)"
            suffix += 1
        }

        configuration.shortcuts.append(
            ShortcutDefinition(
                id: identifier,
                name: String(displayName.prefix(80)),
                bundleIdentifier: bundleIdentifier,
                key: "",
                modifiers: [],
                enabled: false,
                launchIfNeeded: true
            )
        )
        searchText = ""
        setFeedback("\(displayName) added. Record a shortcut, then enable it.")
    }

    func removeShortcut(id: String) {
        configuration.shortcuts.removeAll { $0.id == id }
        setFeedback("Shortcut removed. Save to apply the change.")
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            setFeedback(
                launchAtLoginEnabled
                    ? "KeyChord will launch when you log in."
                    : "Launch at login is off."
            )
        } catch {
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            setFeedback(error.localizedDescription, isError: true)
        }
    }

    func revealConfiguration() {
        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
    }

    func updateRegistrationIssues(_ issues: [String: String]) {
        registrationIssues = issues
    }

    func clearFeedback() {
        feedbackSequence += 1
        feedbackMessage = nil
        feedbackIsError = false
    }

    /// Sets the save-bar feedback message. Informational messages dismiss
    /// themselves after a few seconds; errors stay until the next action.
    private func setFeedback(_ message: String?, isError: Bool = false) {
        feedbackSequence += 1
        let sequence = feedbackSequence
        feedbackMessage = message
        feedbackIsError = isError
        guard message != nil, !isError else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self, self.feedbackSequence == sequence else { return }
            self.clearFeedback()
        }
    }

    private func slug(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let transformed = value.lowercased().unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(String(scalar)) : "-"
        }
        let collapsed = String(transformed)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return String((collapsed.isEmpty ? "application" : collapsed).prefix(64))
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case shortcuts
    case general
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shortcuts: "Shortcuts"
        case .general: "General"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .shortcuts: "command.square"
        case .general: "gearshape"
        case .about: "info.circle"
        }
    }
}
