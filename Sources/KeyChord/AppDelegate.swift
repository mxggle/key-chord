import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let configurationStore: ConfigurationStore
    private let hotKeyManager = HotKeyManager()
    private var configuration: SwitcherConfiguration?
    private var registrations: [HotKeyRegistration] = []
    private var loadError: Error?
    private var statusItem: NSStatusItem?
    private var settingsWindowController: SettingsWindowController?

    override init() {
        do {
            configurationStore = try ConfigurationStore()
        } catch {
            let fallbackURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("KeyChord-config.json")
            configurationStore = ConfigurationStore(fileURL: fallbackURL)
            loadError = error
        }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        reloadConfiguration()
        if CommandLine.arguments.contains("--diagnose-status-item") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
                printStatusItemDiagnostics()
                NSApp.terminate(nil)
            }
            return
        }
        if CommandLine.arguments.contains("--trace-status-item") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
                printStatusItemDiagnostics()
            }
        }
        // A menu-bar app should stay out of the way at launch (especially when
        // registered as a login item). Only open Settings when explicitly asked
        // or when the configuration needs attention.
        if CommandLine.arguments.contains("--show-settings") || loadError != nil {
            DispatchQueue.main.async { [self] in
                openSettings()
            }
        }
    }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        // Finder sends this when the user explicitly opens an app that does not
        // handle documents. Keep login-item launches quiet, but make opening the
        // app bundle a reliable way to reach Settings if its menu-bar item is
        // hidden or crowded out.
        openSettings()
        return true
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        openSettings()
        return true
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = item.button else {
            statusItem = item
            return
        }

        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        let icon = (
            NSImage(systemSymbolName: "arrow.2.squarepath", accessibilityDescription: "KeyChord")
            ?? NSImage(systemSymbolName: "switch.2", accessibilityDescription: "KeyChord")
            ?? NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "KeyChord")
        )?.withSymbolConfiguration(symbolConfig)

        icon?.isTemplate = true
        button.image = icon
        button.imagePosition = .imageOnly
        button.title = ""
        button.setAccessibilityLabel("KeyChord")
        button.toolTip = "KeyChord"
        statusItem = item
        applyStatusItemVisibility(configuration?.settings.showMenuBarIcon ?? true)
        rebuildMenu()
    }

    private func printStatusItemDiagnostics() {
        guard let statusItem else {
            print("statusItem=nil")
            return
        }
        guard let button = statusItem.button else {
            print("statusItem.visible=\(statusItem.isVisible) button=nil")
            return
        }
        let windowDescription = button.window.map {
            "number=\($0.windowNumber) frame=\($0.frame) visible=\($0.isVisible)"
        } ?? "nil"
        print(
            "statusItem.visible=\(statusItem.isVisible) "
                + "length=\(statusItem.length) "
                + "button.frame=\(button.frame) "
                + "button.title=\(button.title.debugDescription) "
                + "window=\(windowDescription)"
        )
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let heading = NSMenuItem(title: "KeyChord", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)

        if let loadError {
            let errorItem = NSMenuItem(
                title: "Configuration error: \(loadError.localizedDescription)",
                action: nil,
                keyEquivalent: ""
            )
            errorItem.isEnabled = false
            menu.addItem(errorItem)
        } else {
            let successfulCount = registrations.filter { $0.error == nil }.count
            let status = NSMenuItem(
                title: "\(successfulCount) of \(registrations.count) shortcuts active",
                action: nil,
                keyEquivalent: ""
            )
            status.isEnabled = false
            menu.addItem(status)

            if !NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.stairways.keyboardmaestro.engine"
            ).isEmpty {
                let warning = NSMenuItem(
                    title: "⚠︎ Disable Keyboard Maestro's App switcher group",
                    action: nil,
                    keyEquivalent: ""
                )
                warning.isEnabled = false
                menu.addItem(warning)
            }

            if configuration?.settings.showShortcutsInMenu ?? true {
                for registration in registrations {
                    let item = NSMenuItem(
                        title: "\(registration.shortcut.displayShortcut)  \(registration.shortcut.name)",
                        action: #selector(activateShortcut(_:)),
                        keyEquivalent: ""
                    )
                    item.target = self
                    item.representedObject = registration.shortcut
                    item.image = menuIcon(for: registration.shortcut.bundleIdentifier)
                    if registration.error != nil {
                        let icon = NSImage(
                            systemSymbolName: "exclamationmark.triangle.fill",
                            accessibilityDescription: "Shortcut unavailable"
                        )
                        icon?.isTemplate = true
                        item.image = icon
                        item.toolTip = "macOS refused to register \(registration.shortcut.displayShortcut). Another app may already use it."
                    } else {
                        item.toolTip = "Activate \(registration.shortcut.name)"
                    }
                    menu.addItem(item)
                }
            }
        }

        menu.addItem(.separator())
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let reloadItem = NSMenuItem(
            title: "Reload Configuration",
            action: #selector(reloadConfiguration),
            keyEquivalent: "r"
        )
        reloadItem.target = self
        menu.addItem(reloadItem)

        let openItem = NSMenuItem(
            title: "Open Configuration File",
            action: #selector(openConfiguration),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)

        let loginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: "Quit KeyChord",
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem?.menu = menu
    }

    private func menuIcon(for bundleIdentifier: String) -> NSImage? {
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else {
            let icon = NSImage(
                systemSymbolName: "app.dashed",
                accessibilityDescription: "Application not installed"
            )
            icon?.isTemplate = true
            return icon
        }
        let icon = NSWorkspace.shared.icon(forFile: applicationURL.path)
        icon.size = NSSize(width: 18, height: 18)
        return icon
    }

    @objc private func activateShortcut(_ sender: NSMenuItem) {
        guard let shortcut = sender.representedObject as? ShortcutDefinition else { return }
        hotKeyManager.perform(shortcut)
    }

    private func publishRegistrationIssues() {
        var issues: [String: String] = [:]
        for registration in registrations where registration.error != nil {
            issues[registration.shortcut.id] =
                "macOS refused to register \(registration.shortcut.displayShortcut) (error \(registration.error ?? 0)). Another app may already use it."
        }
        settingsWindowController?.viewModel.updateRegistrationIssues(issues)
    }

    @objc private func reloadConfiguration() {
        do {
            let loadedConfiguration = try configurationStore.loadOrCreate()
            configuration = loadedConfiguration
            registrations = hotKeyManager.register(loadedConfiguration.shortcuts)
            loadError = nil
            applyDockVisibility(loadedConfiguration.settings.showDockIcon)
            applyStatusItemVisibility(loadedConfiguration.settings.showMenuBarIcon)
            settingsWindowController?.viewModel.replacePersistedConfiguration(
                loadedConfiguration
            )
        } catch {
            hotKeyManager.unregisterAll()
            configuration = nil
            registrations = []
            loadError = error
            applyDockVisibility(true)
            applyStatusItemVisibility(true)
        }
        publishRegistrationIssues()
        rebuildMenu()
    }

    @objc private func openSettings() {
        do {
            let currentConfiguration = try configurationStore.loadOrCreate()
            if let settingsWindowController {
                settingsWindowController.viewModel.replacePersistedConfiguration(
                    currentConfiguration
                )
                settingsWindowController.show()
                return
            }

            let viewModel = SettingsViewModel(
                configuration: currentConfiguration,
                store: configurationStore
            ) { [weak self] updatedConfiguration in
                self?.applyConfiguration(updatedConfiguration)
            }
            let controller = SettingsWindowController(viewModel: viewModel)
            settingsWindowController = controller
            publishRegistrationIssues()
            controller.show()
        } catch {
            loadError = error
            rebuildMenu()
        }
    }

    private func applyConfiguration(_ updatedConfiguration: SwitcherConfiguration) {
        configuration = updatedConfiguration
        registrations = hotKeyManager.register(updatedConfiguration.shortcuts)
        loadError = nil
        applyDockVisibility(updatedConfiguration.settings.showDockIcon)
        applyStatusItemVisibility(updatedConfiguration.settings.showMenuBarIcon)
        publishRegistrationIssues()
        rebuildMenu()
    }

    private func applyDockVisibility(_ showDockIcon: Bool) {
        let policy: NSApplication.ActivationPolicy = showDockIcon ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
    }

    private func applyStatusItemVisibility(_ showMenuBarIcon: Bool) {
        statusItem?.isVisible = showMenuBarIcon
    }

    @objc private func openConfiguration() {
        do {
            _ = try configurationStore.loadOrCreate()
            NSWorkspace.shared.open(configurationStore.fileURL)
        } catch {
            loadError = error
            rebuildMenu()
        }
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            loadError = nil
        } catch {
            loadError = error
        }
        rebuildMenu()
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }
}
