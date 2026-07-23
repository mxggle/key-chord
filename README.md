# App Switcher

[![Version](https://img.shields.io/badge/version-1.1.0-blue.svg)](packaging/Info.plist)
[![macOS](https://img.shields.io/badge/macOS-14.0%2B-apple.svg)](Package.swift)
[![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)](Package.swift)

**App Switcher** is a high-performance, lightweight native macOS menu-bar and menu-driven application designed to replace heavy application-switching macros (such as Keyboard Maestro app switcher setups). 

It utilizes native Carbon global hotkeys and AppKit application activation—delivering instant, low-latency app switching **without requiring Accessibility or Input Monitoring permissions**.

---

## 🌟 Key Features

- **⚡ Instant App Switching**: Activate or bring all windows of target applications to the front with configurable global hotkeys.
- **🔄 Smart Window Toggling**: Pressing the same hotkey while a target application is active automatically hides it.
- **🛡️ Permission-Free**: Operates natively via Carbon hotkeys and AppKit activation services—no Accessibility, Accessibility APIs, or Input Monitoring privileges needed.
- **⚙️ Native SwiftUI Settings**: Comprehensive preferences panel to add/remove apps, record hotkeys, toggle launch-on-login, configure Dock & menu-bar icon visibility, and tune per-app activation rules.
- **🚀 Optional App Launching**: Per-shortcut setting (`launchIfNeeded`) to optionally launch stopped target applications upon pressing their hotkey.
- **⚠️ Conflict Detection & Migration**: Built-in detection for running Keyboard Maestro instances and system hotkey collisions, with clear UI indicators.
- **🛠️ Rich Command-Line Interface**: CLI support for configuration validation, hotkey collision probing, default config dumping, version inspection, and diagnostic self-tests.

---

## 📋 Requirements

| Requirement | Specification |
| :--- | :--- |
| **Operating System** | macOS 14.0 (Sonoma) or later |
| **Developer Tools** | Swift 6.2 / Xcode 15+ toolchain |
| **Permissions** | None (No Accessibility or Input Monitoring required) |

---

## 🚀 Quick Start & Installation

### 1. Build & Run from Source

To run self-tests and start the application in development mode:

```bash
# Run internal self-tests
swift run AppSwitcher --self-test

# Launch App Switcher directly
swift run AppSwitcher
```

### 2. Package as a Native macOS Application

Use the provided packaging script to compile the release binary and assemble a signed `.app` bundle:

```bash
./scripts/package-app.sh
```

The compiled application bundle will be created at:
```text
.build/App Switcher.app
```

> **Note on Code Signing**: The build script automatically signs the bundle using the first available local code-signing identity, falling back to ad-hoc signing (`-`) if none exists.

---

## ⚙️ Configuration

On initial execution, App Switcher creates a default configuration file at:

```text
~/Library/Application Support/AppSwitcher/config.json
```

### Configuration Schema

```json
{
  "version": 1,
  "settings": {
    "showDockIcon": true,
    "showMenuBarIcon": true,
    "launchAtLogin": false
  },
  "shortcuts": [
    {
      "id": "finder",
      "name": "Finder",
      "bundleIdentifier": "com.apple.finder",
      "key": "1",
      "modifiers": ["option"],
      "enabled": true,
      "launchIfNeeded": true,
      "hideWhenFrontmost": true,
      "activateAllWindows": true
    }
  ]
}
```

### Configuration Fields

- **`settings`**:
  - `showDockIcon`: Toggles visibility of the application in the macOS Dock.
  - `showMenuBarIcon`: Toggles visibility of the status item in the menu bar.
  - `launchAtLogin`: Configures automatic startup via `SMAppService`.
- **`shortcuts[]`**:
  - `id`: Unique identifier string for the shortcut entry.
  - `name`: Display label shown in the UI and menu.
  - `bundleIdentifier`: macOS bundle identifier for target application (e.g., `com.apple.finder`).
  - `key`: Key character or code representation.
  - `modifiers`: Array of modifier strings (`"command"`, `"control"`, `"option"`, `"shift"`).
  - `enabled`: Boolean toggle to enable or disable the shortcut.
  - `launchIfNeeded`: If `true`, launches target application when it is not currently running.
  - `hideWhenFrontmost`: If `true`, pressing hotkey when target app is active hides the app.
  - `activateAllWindows`: If `true`, brings all app windows to front; if `false`, brings front window only.

> **Security & Validation**: Configuration files are strictly validated before registering hotkeys. Malformed, duplicate, or invalid definitions fail closed, leaving shortcuts safely unregistered without crashing.

---

## 💻 Command-Line Options (CLI)

App Switcher includes utility flags for automation, diagnostics, and testing:

| Flag | Description |
| :--- | :--- |
| `-v`, `--version` | Display application name and version details |
| `--show-settings` | Force open the settings window on launch |
| `--probe-hotkeys` | Test hotkey registration against system conflicts without starting the app loop |
| `--validate-config <PATH>` | Validate a specified `config.json` file for structural correctness |
| `--print-default-config` | Output default configuration JSON to stdout |
| `--self-test` | Execute internal diagnostic and behavioral unit tests |

### Examples

```bash
# Check version
AppSwitcher --version
# Output: App Switcher v1.1.0 (build 2)

# Test shortcut registration for system conflicts
AppSwitcher --probe-hotkeys

# Validate custom configuration file
AppSwitcher --validate-config ~/Desktop/my_config.json
```

---

## 🔄 Migrating from Keyboard Maestro

If migrating from Keyboard Maestro:
1. **Parallel Execution**: Both Keyboard Maestro and App Switcher can temporarily receive the same hotkey, which may cause activation races.
2. **Conflict Warnings**: App Switcher displays a migration banner in the status menu when Keyboard Maestro Engine is detected running.
3. **Completing Migration**: Disable your Keyboard Maestro `App switcher` macro group or quit the Keyboard Maestro Engine once App Switcher is tested and configured.

---

## 📁 Repository Structure

```text
app-switcher/
├── Package.swift               # Swift Package Manager manifest
├── README.md                   # Project documentation
├── Sources/
│   └── AppSwitcher/
│       ├── AppDelegate.swift   # App lifecycle, menu item & Dock management
│       ├── ApplicationSwitcher.swift # Window activation & hide engine
│       ├── ConfigurationStore.swift  # Config storage & JSON persistence
│       ├── HotKeyManager.swift # Carbon global hotkey registration
│       ├── Models.swift        # Data models, validation & version info
│       ├── SelfTest.swift      # Built-in diagnostic test suite
│       ├── SettingsView.swift  # SwiftUI settings panel & preferences
│       ├── SettingsViewModel.swift # Settings state manager
│       ├── SettingsWindowController.swift # Settings window manager
│       ├── ShortcutRecorder.swift # Key recorder control
│       └── main.swift          # Entry point & CLI argument parser
├── packaging/
│   └── Info.plist              # macOS App bundle property list
└── scripts/
    └── package-app.sh          # Build & code-signing script
```

---

## 🧪 Testing

To run internal self-tests for hotkey handling, shortcut key code resolution, application state toggling, and configuration validation:

```bash
swift run AppSwitcher --self-test
```

---

## 📄 Versioning

Current Version: **`1.1.0`** (Build `2`)

Changes in **v1.1.0**:
- Added native SwiftUI settings window with shortcut recorder.
- Added support for launch at login, menu bar / Dock visibility settings.
- Added per-app window activation & hide controls.
- Added `--version` CLI flag and centralized version management.
