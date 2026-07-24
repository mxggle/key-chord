import AppKit

protocol RunningApplicationControlling: AnyObject {
    var isActive: Bool { get }
    var isHidden: Bool { get }
    @discardableResult func hide() -> Bool
    @discardableResult func unhide() -> Bool
    @discardableResult func activateAllWindows() -> Bool
    @discardableResult func activateFrontWindow() -> Bool
}

extension NSRunningApplication: RunningApplicationControlling {
    func activateAllWindows() -> Bool {
        activate(options: [.activateAllWindows])
    }

    func activateFrontWindow() -> Bool {
        activate(options: [])
    }
}

protocol WorkspaceControlling: AnyObject {
    func runningApplications(bundleIdentifier: String) -> [RunningApplicationControlling]
    func openApplication(bundleIdentifier: String)
}

final class SystemWorkspace: WorkspaceControlling {
    func runningApplications(bundleIdentifier: String) -> [RunningApplicationControlling] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
    }

    func openApplication(bundleIdentifier: String) {
        let workspace = NSWorkspace.shared
        guard let applicationURL = workspace.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else {
            NSLog("KeyChord could not find an application for %@", bundleIdentifier)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        workspace.openApplication(at: applicationURL, configuration: configuration) { _, error in
            if let error {
                NSLog("KeyChord could not launch %@: %@", bundleIdentifier, error.localizedDescription)
            }
        }
    }
}

final class ApplicationSwitcher {
    private let workspace: WorkspaceControlling

    init(workspace: WorkspaceControlling = SystemWorkspace()) {
        self.workspace = workspace
    }

    func perform(_ shortcut: ShortcutDefinition) {
        NSLog("KeyChord performing shortcut: %@ (%@)", shortcut.name, shortcut.bundleIdentifier)
        if let application = workspace.runningApplications(
            bundleIdentifier: shortcut.bundleIdentifier
        ).first {
            if application.isActive {
                if shortcut.hideWhenFrontmost {
                    NSLog("KeyChord hiding frontmost app: %@", shortcut.name)
                    _ = application.hide()
                }
                return
            }

            if application.isHidden {
                _ = application.unhide()
            }
            let didActivate: Bool
            if shortcut.activateAllWindows {
                didActivate = application.activateAllWindows()
            } else {
                didActivate = application.activateFrontWindow()
            }
            NSLog("KeyChord direct activation result for %@: %d", shortcut.name, didActivate ? 1 : 0)
            if !didActivate {
                NSLog(
                    "KeyChord activation was refused for %@; retrying through NSWorkspace",
                    shortcut.bundleIdentifier
                )
                workspace.openApplication(bundleIdentifier: shortcut.bundleIdentifier)
            }
            return
        }

        if shortcut.launchIfNeeded {
            NSLog("KeyChord launching stopped app: %@ (%@)", shortcut.name, shortcut.bundleIdentifier)
            workspace.openApplication(bundleIdentifier: shortcut.bundleIdentifier)
        } else {
            NSLog("KeyChord app %@ is not running and launchIfNeeded is false", shortcut.name)
        }
    }
}
