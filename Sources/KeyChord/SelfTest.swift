import Foundation

enum SelfTest {
    static func run() -> [String] {
        var failures: [String] = []

        expect("default configuration validates", failures: &failures) {
            try ConfigurationValidator.validate(ConfigurationStore.defaultConfiguration)
        }
        check(
            ConfigurationStore.defaultConfiguration.shortcuts.count == 15,
            "default configuration has 15 shortcuts",
            failures: &failures
        )
        check(!AppInfo.version.isEmpty, "app version is non-empty", failures: &failures)
        check(KeyCodeResolver.resolve("1") == 18, "1 uses key code 18", failures: &failures)
        check(KeyCodeResolver.resolve("A") == 0, "A uses key code 0", failures: &failures)
        check(KeyCodeResolver.resolve("Q") == 12, "Q uses key code 12", failures: &failures)
        check(KeyCodeResolver.resolve("R") == 15, "R uses key code 15", failures: &failures)

        var pressGate = HotKeyPressGate()
        check(
            pressGate.acceptPress(1),
            "initial hot-key press is accepted",
            failures: &failures
        )
        check(
            !pressGate.acceptPress(1),
            "held-key repeat is ignored",
            failures: &failures
        )
        check(
            pressGate.acceptPress(2),
            "a different hot key remains responsive",
            failures: &failures
        )
        pressGate.release(1)
        check(
            pressGate.acceptPress(1),
            "hot key is accepted again after release",
            failures: &failures
        )
        pressGate.reset()
        check(
            pressGate.acceptPress(1),
            "registration reset clears held-key state",
            failures: &failures
        )

        let displayShortcut = makeShortcut(
            modifiers: [.command, .shift, .option, .control]
        )
        check(
            displayShortcut.displayShortcut == "⌃⌥⇧⌘A",
            "modifier symbols use standard Mac order",
            failures: &failures
        )

        expectFailure("duplicate enabled hot key is rejected", failures: &failures) {
            let configuration = SwitcherConfiguration(
                version: 1,
                shortcuts: [makeShortcut(id: "one"), makeShortcut(id: "two")]
            )
            try ConfigurationValidator.validate(configuration)
        }

        expect("legacy configuration gains modern defaults", failures: &failures) {
            let legacyJSON = #"{"version":1,"shortcuts":[{"id":"legacy","name":"Legacy","bundleIdentifier":"com.example.legacy","key":"a","modifiers":["option"],"enabled":true,"launchIfNeeded":false}]}"#
            let decoded = try JSONDecoder().decode(
                SwitcherConfiguration.self,
                from: Data(legacyJSON.utf8)
            )
            if decoded.settings != .defaults
                || decoded.settings.showMenuBarIcon != true
                || decoded.shortcuts.first?.hideWhenFrontmost != true
                || decoded.shortcuts.first?.activateAllWindows != true {
                throw SelfTestError.failedExpectation
            }
        }

        let activeApplication = FakeRunningApplication(isActive: true, isHidden: false)
        let activeWorkspace = FakeWorkspace(applications: [activeApplication])
        ApplicationSwitcher(workspace: activeWorkspace).perform(makeShortcut())
        check(
            activeApplication.hideCount == 1 && activeApplication.activateCount == 0,
            "frontmost app is hidden",
            failures: &failures
        )

        let leaveActiveApplication = FakeRunningApplication(isActive: true, isHidden: false)
        let leaveActiveWorkspace = FakeWorkspace(applications: [leaveActiveApplication])
        var leaveActiveShortcut = makeShortcut()
        leaveActiveShortcut.hideWhenFrontmost = false
        ApplicationSwitcher(workspace: leaveActiveWorkspace).perform(leaveActiveShortcut)
        check(
            leaveActiveApplication.hideCount == 0,
            "frontmost app remains visible when hiding is disabled",
            failures: &failures
        )

        let hiddenApplication = FakeRunningApplication(isActive: false, isHidden: true)
        let hiddenWorkspace = FakeWorkspace(applications: [hiddenApplication])
        ApplicationSwitcher(workspace: hiddenWorkspace).perform(makeShortcut())
        check(
            hiddenApplication.unhideCount == 1 && hiddenApplication.activateCount == 1,
            "hidden app is unhidden and activated",
            failures: &failures
        )

        let frontWindowApplication = FakeRunningApplication(isActive: false, isHidden: false)
        let frontWindowWorkspace = FakeWorkspace(applications: [frontWindowApplication])
        var frontWindowShortcut = makeShortcut()
        frontWindowShortcut.activateAllWindows = false
        ApplicationSwitcher(workspace: frontWindowWorkspace).perform(frontWindowShortcut)
        check(
            frontWindowApplication.frontWindowActivationCount == 1
                && frontWindowApplication.allWindowsActivationCount == 0,
            "front-window-only activation is respected",
            failures: &failures
        )

        let refusedApplication = FakeRunningApplication(
            isActive: false,
            isHidden: false,
            activationSucceeds: false
        )
        let refusedWorkspace = FakeWorkspace(applications: [refusedApplication])
        ApplicationSwitcher(workspace: refusedWorkspace).perform(makeShortcut())
        check(
            refusedWorkspace.openedBundleIdentifiers == ["com.example.target"],
            "failed direct activation retries through the workspace",
            failures: &failures
        )

        let stoppedWorkspace = FakeWorkspace(applications: [])
        ApplicationSwitcher(workspace: stoppedWorkspace).perform(
            makeShortcut(launchIfNeeded: false)
        )
        check(
            stoppedWorkspace.openedBundleIdentifiers.isEmpty,
            "stopped app remains stopped by default",
            failures: &failures
        )

        let launchWorkspace = FakeWorkspace(applications: [])
        ApplicationSwitcher(workspace: launchWorkspace).perform(
            makeShortcut(launchIfNeeded: true)
        )
        check(
            launchWorkspace.openedBundleIdentifiers == ["com.example.target"],
            "stopped app launches when configured",
            failures: &failures
        )

        return failures
    }

    private static func check(
        _ condition: @autoclosure () -> Bool,
        _ message: String,
        failures: inout [String]
    ) {
        if !condition() {
            failures.append(message)
        }
    }

    private static func expect(
        _ message: String,
        failures: inout [String],
        operation: () throws -> Void
    ) {
        do {
            try operation()
        } catch {
            failures.append("\(message): \(error.localizedDescription)")
        }
    }

    private static func expectFailure(
        _ message: String,
        failures: inout [String],
        operation: () throws -> Void
    ) {
        do {
            try operation()
            failures.append(message)
        } catch {
            // Expected.
        }
    }

    private static func makeShortcut(
        id: String = "target",
        modifiers: [ShortcutModifier] = [.option],
        launchIfNeeded: Bool = false
    ) -> ShortcutDefinition {
        ShortcutDefinition(
            id: id,
            name: "Target",
            bundleIdentifier: "com.example.target",
            key: "a",
            modifiers: modifiers,
            enabled: true,
            launchIfNeeded: launchIfNeeded
        )
    }
}

private enum SelfTestError: Error {
    case failedExpectation
}

private final class FakeRunningApplication: RunningApplicationControlling {
    var isActive: Bool
    var isHidden: Bool
    var hideCount = 0
    var unhideCount = 0
    var activateCount = 0
    var allWindowsActivationCount = 0
    var frontWindowActivationCount = 0
    let activationSucceeds: Bool

    init(isActive: Bool, isHidden: Bool, activationSucceeds: Bool = true) {
        self.isActive = isActive
        self.isHidden = isHidden
        self.activationSucceeds = activationSucceeds
    }

    func hide() -> Bool {
        hideCount += 1
        return true
    }

    func unhide() -> Bool {
        unhideCount += 1
        return true
    }

    func activateAllWindows() -> Bool {
        activateCount += 1
        allWindowsActivationCount += 1
        return activationSucceeds
    }

    func activateFrontWindow() -> Bool {
        activateCount += 1
        frontWindowActivationCount += 1
        return activationSucceeds
    }
}

private final class FakeWorkspace: WorkspaceControlling {
    let applications: [RunningApplicationControlling]
    var openedBundleIdentifiers: [String] = []

    init(applications: [RunningApplicationControlling]) {
        self.applications = applications
    }

    func runningApplications(bundleIdentifier: String) -> [RunningApplicationControlling] {
        applications
    }

    func openApplication(bundleIdentifier: String) {
        openedBundleIdentifiers.append(bundleIdentifier)
    }
}
