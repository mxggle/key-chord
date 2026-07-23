import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var showResetConfirmation = false

    private let contentMaxWidth: CGFloat = 720
    private var containerShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 840, minHeight: 580)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Restore default settings?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Restore Defaults", role: .destructive) {
                viewModel.resetToDefaults()
            }
        } message: {
            Text("Your current shortcut list will be replaced after you save.")
        }
    }

    private var sidebar: some View {
        List(SettingsSection.allCases, selection: $viewModel.selectedSection) { section in
            Button {
                viewModel.selectedSection = section
            } label: {
                Label(section.title, systemImage: section.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .tag(section)
            .badge(section == .shortcuts ? viewModel.configuration.shortcuts.count : 0)
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        .navigationTitle("App Switcher")
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Divider()
                Label("Native · Private · Fast", systemImage: "leaf.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
            }
            .background(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch viewModel.selectedSection ?? .shortcuts {
        case .shortcuts:
            shortcutsPage
        case .general:
            generalPage
        case .about:
            aboutPage
        }
    }

    // MARK: - Shortcuts

    private var shortcutsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                pageHeader(
                    title: "Keyboard Shortcuts",
                    subtitle: "Switch to an app instantly. Press the same shortcut again to hide it."
                )

                if let validationMessage = viewModel.validationMessage {
                    validationBanner(validationMessage)
                }

                if viewModel.configuration.shortcuts.isEmpty {
                    emptyShortcutsState
                } else if viewModel.filteredShortcuts.isEmpty {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "magnifyingglass",
                        description: Text("No applications match your search.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    shortcutListSection
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) { saveBar }
        .searchable(
            text: $viewModel.searchText,
            placement: .toolbar,
            prompt: "Search apps or shortcuts"
        )
        .toolbar { addApplicationToolbar }
    }

    private var shortcutListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Applications")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                shortcutStatus
            }
            .padding(.horizontal, 2)

            VStack(spacing: 0) {
                ForEach(viewModel.filteredShortcuts) { shortcut in
                    if let binding = viewModel.binding(forShortcutID: shortcut.id) {
                        ShortcutRow(
                            shortcut: binding,
                            issue: viewModel.registrationIssues[shortcut.id]
                        ) {
                            viewModel.removeShortcut(id: shortcut.id)
                        }
                        if shortcut.id != viewModel.filteredShortcuts.last?.id {
                            Divider().padding(.leading, 64)
                        }
                    }
                }
            }
            .clipShape(containerShape)
            .background(Color(nsColor: .controlBackgroundColor), in: containerShape)
            .overlay {
                containerShape.strokeBorder(
                    Color(nsColor: .separatorColor).opacity(0.5),
                    lineWidth: 1
                )
            }
            .animation(.smooth, value: viewModel.filteredShortcuts)
        }
    }

    @ViewBuilder
    private var shortcutStatus: some View {
        let isSearching = !viewModel.searchText
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isSearching {
            Text("\(viewModel.filteredShortcuts.count) of \(viewModel.configuration.shortcuts.count)")
                .font(.callout)
                .foregroundStyle(.tertiary)
        } else {
            let enabledCount = viewModel.configuration.shortcuts.filter(\.enabled).count
            HStack(spacing: 5) {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
                Text("\(enabledCount) active")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyShortcutsState: some View {
        VStack(spacing: 10) {
            Image(systemName: "command.square")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 2)
            Text("No Applications Yet")
                .font(.title3.weight(.semibold))
            Text("Add an application to create your first keyboard shortcut.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button(action: viewModel.addApplication) {
                Label("Add Application", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 72)
    }

    // MARK: - General

    private var generalPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                pageHeader(
                    title: "General",
                    subtitle: "Choose how App Switcher starts and what appears in its menu."
                )

                settingsGroup("Startup") {
                    SettingsToggleRow(
                        title: "Launch at login",
                        subtitle: "Keep your shortcuts available after every restart.",
                        symbol: "arrow.up.right.circle.fill",
                        color: .blue,
                        isOn: Binding(
                            get: { viewModel.launchAtLoginEnabled },
                            set: { viewModel.setLaunchAtLogin($0) }
                        )
                    )
                    Divider().padding(.leading, 54)
                    SettingsToggleRow(
                        title: "Show in Dock",
                        subtitle: "Keep a permanent Dock icon for reliable access to Settings.",
                        symbol: "dock.rectangle",
                        color: .indigo,
                        isOn: $viewModel.configuration.settings.showDockIcon
                    )
                }

                settingsGroup("Menu Bar") {
                    SettingsToggleRow(
                        title: "Show shortcut list",
                        subtitle: "Display every active app shortcut in the menu-bar menu.",
                        symbol: "list.bullet.rectangle.fill",
                        color: .purple,
                        isOn: $viewModel.configuration.settings.showShortcutsInMenu
                    )
                    Divider().padding(.leading, 54)
                    SettingsToggleRow(
                        title: "Keyboard Maestro warning",
                        subtitle: "Warn when both tools may respond to the same shortcut.",
                        symbol: "exclamationmark.triangle.fill",
                        color: .orange,
                        isOn: $viewModel.configuration.settings.showKeyboardMaestroWarning
                    )
                }

                settingsGroup("Configuration") {
                    HStack(spacing: 12) {
                        SettingsGlyph(symbol: "folder.fill", color: .gray)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Configuration file")
                                .font(.body.weight(.medium))
                            Text("Stored locally in Application Support")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Show in Finder", action: viewModel.revealConfiguration)
                            .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }

                HStack {
                    Button("Restore Defaults", role: .destructive) {
                        showResetConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 28)
            .frame(maxWidth: contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) { saveBar }
        .toolbar { addApplicationToolbar }
    }

    // MARK: - About

    private var aboutPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                pageHeader(
                    title: "About App Switcher",
                    subtitle: "A focused, native replacement for application-switching macros."
                )

                HStack(spacing: 18) {
                    aboutIcon
                        .frame(width: 84, height: 84)
                        .shadow(color: .indigo.opacity(0.25), radius: 14, y: 7)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("App Switcher")
                            .font(.system(size: 24, weight: .bold))
                        Text("Version \(appVersion)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("Built with Swift, SwiftUI, AppKit, and Carbon.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                settingsGroup("Designed for focus") {
                    FeatureRow(
                        symbol: "lock.shield.fill",
                        color: .green,
                        title: "Private by design",
                        detail: "No analytics, network access, or account required."
                    )
                    Divider().padding(.leading, 54)
                    FeatureRow(
                        symbol: "hand.raised.slash.fill",
                        color: .blue,
                        title: "No accessibility permission",
                        detail: "Global shortcuts use the native system hot-key API."
                    )
                    Divider().padding(.leading, 54)
                    FeatureRow(
                        symbol: "bolt.fill",
                        color: .orange,
                        title: "Lightweight",
                        detail: "Runs quietly in the menu bar and does one job well."
                    )
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 28)
            .frame(maxWidth: contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .toolbar { addApplicationToolbar }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? AppInfo.version
    }

    @ToolbarContentBuilder
    private var addApplicationToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(action: viewModel.addApplication) {
                Label("Add Application", systemImage: "plus")
            }
            .keyboardShortcut("n")
            .help("Add Application (⌘N)")
        }
    }

    /// Shows the real app icon once the bundle ships one; until then, falls
    /// back to a branded tile instead of the generic executable icon.
    @ViewBuilder
    private var aboutIcon: some View {
        if Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") != nil
            || Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") != nil {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .indigo],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }

    // MARK: - Shared components

    private func pageHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 24, weight: .bold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func validationBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(0.1), in: containerShape)
        .overlay {
            containerShape.strokeBorder(Color.orange.opacity(0.25), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var saveBar: some View {
        // Only take up space when there are unsaved changes or a message to
        // show; an always-visible disabled bar adds noise without value.
        if viewModel.isDirty || viewModel.feedbackMessage != nil {
            HStack(spacing: 12) {
                if let feedback = viewModel.feedbackMessage {
                    Label(
                        feedback,
                        systemImage: viewModel.feedbackIsError
                            ? "exclamationmark.circle.fill"
                            : "checkmark.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(viewModel.feedbackIsError ? .red : .secondary)
                    .lineLimit(1)
                    .transition(.opacity)
                }
                Spacer()
                Button("Revert", action: viewModel.revert)
                    .disabled(!viewModel.isDirty)
                Button("Save Changes", action: viewModel.save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!viewModel.isDirty || viewModel.validationMessage != nil)
            }
            .animation(.smooth, value: viewModel.feedbackMessage)
            .padding(.horizontal, 20)
            .frame(height: 54)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) { Divider() }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func settingsGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
            VStack(spacing: 0) {
                content()
            }
            .background(Color(nsColor: .controlBackgroundColor), in: containerShape)
            .overlay {
                containerShape.strokeBorder(
                    Color(nsColor: .separatorColor).opacity(0.5),
                    lineWidth: 1
                )
            }
        }
    }
}

// MARK: - Shortcut row

private struct ShortcutRow: View {
    @Binding var shortcut: ShortcutDefinition
    var issue: String?
    let onRemove: () -> Void

    @State private var isHovering = false
    @State private var isRenaming = false
    @State private var draftName = ""

    var body: some View {
        HStack(spacing: 12) {
            applicationIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(shortcut.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(shortcut.bundleIdentifier)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .opacity(shortcut.enabled ? 1 : 0.55)

            Spacer(minLength: 16)

            if let issue {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .imageScale(.medium)
                    .help(issue)
                    .accessibilityLabel("Shortcut registration problem")
            }

            ShortcutRecorder(key: $shortcut.key, modifiers: $shortcut.modifiers)
                .frame(width: 132, height: 26)

            Toggle("", isOn: $shortcut.enabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(shortcut.key.isEmpty || shortcut.modifiers.isEmpty)
                .help(
                    shortcut.key.isEmpty
                        ? "Record a shortcut before enabling this app."
                        : "Enable shortcut"
                )
                .accessibilityLabel("Enable shortcut for \(shortcut.name)")

            Menu {
                rowActions
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More actions")
            .accessibilityLabel("More actions for \(shortcut.name)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(isHovering ? 0.04 : 0))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.snappy(duration: 0.15), value: isHovering)
        .contextMenu { rowActions }
        .alert("Rename Application", isPresented: $isRenaming) {
            TextField("Application name", text: $draftName)
            Button("Cancel", role: .cancel) {}
            Button("Rename", action: commitRename)
                .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("This name appears in your shortcut list.")
        }
    }

    @ViewBuilder
    private var rowActions: some View {
        Button("Rename…") {
            draftName = shortcut.name
            isRenaming = true
        }
        Divider()
        Toggle("Launch if closed", isOn: $shortcut.launchIfNeeded)
        Toggle("Hide when active", isOn: $shortcut.hideWhenFrontmost)
        Toggle("Activate all windows", isOn: $shortcut.activateAllWindows)
        Divider()
        Button("Remove Application", role: .destructive, action: onRemove)
    }

    private func commitRename() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        shortcut.name = String(trimmed.prefix(80))
    }

    private var applicationIcon: some View {
        Group {
            if let applicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: shortcut.bundleIdentifier
            ) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: applicationURL.path))
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .scaledToFit()
                    .padding(7)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 38, height: 38)
        .saturation(shortcut.enabled ? 1 : 0.35)
        .opacity(shortcut.enabled ? 1 : 0.65)
        .accessibilityHidden(true)
    }
}

// MARK: - Reusable rows

private struct SettingsGlyph: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(
                color.gradient,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            SettingsGlyph(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct FeatureRow: View {
    let symbol: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            SettingsGlyph(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
