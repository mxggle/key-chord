import Carbon
import Foundation

struct HotKeyRegistration: Equatable {
    let shortcut: ShortcutDefinition
    let error: OSStatus?
}

private func carbonHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else {
        return OSStatus(eventNotHandledErr)
    }
    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    return manager.handle(event: event)
}

final class HotKeyManager {
    private static let signature: OSType = 0x4B43_4844 // "KCHD"

    private let switcher: ApplicationSwitcher
    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var shortcutsByID: [UInt32: ShortcutDefinition] = [:]
    private var pressGate = HotKeyPressGate()

    init(switcher: ApplicationSwitcher = ApplicationSwitcher()) {
        self.switcher = switcher
        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            )
        ]
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotKeyHandler,
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        if status != noErr {
            NSLog("KeyChord could not install its hot-key handler: %d", status)
        }
    }

    deinit {
        unregisterAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func register(_ shortcuts: [ShortcutDefinition]) -> [HotKeyRegistration] {
        unregisterAll()
        var results: [HotKeyRegistration] = []

        for (offset, shortcut) in shortcuts.filter(\.enabled).enumerated() {
            guard let keyCode = KeyCodeResolver.resolve(shortcut.key) else {
                results.append(.init(shortcut: shortcut, error: OSStatus(paramErr)))
                continue
            }

            let identifier = UInt32(offset + 1)
            var hotKeyReference: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(
                signature: Self.signature,
                id: identifier
            )
            let status = RegisterEventHotKey(
                keyCode,
                shortcut.carbonModifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                // Non-exclusive registration can return success even while an
                // exclusive registration in another process suppresses every
                // event. Claim ownership so "registered" always means this
                // handler will actually receive the shortcut.
                OptionBits(kEventHotKeyExclusive),
                &hotKeyReference
            )

            if status == noErr, let hotKeyReference {
                hotKeyRefs.append(hotKeyReference)
                shortcutsByID[identifier] = shortcut
                results.append(.init(shortcut: shortcut, error: nil))
            } else {
                results.append(.init(shortcut: shortcut, error: status))
            }
        }

        return results
    }

    func unregisterAll() {
        for reference in hotKeyRefs {
            UnregisterEventHotKey(reference)
        }
        hotKeyRefs.removeAll()
        shortcutsByID.removeAll()
        pressGate.reset()
    }

    /// Performs the same activation flow a hot-key press would trigger.
    /// Used by menu-bar items so clicking an entry matches pressing its shortcut.
    func perform(_ shortcut: ShortcutDefinition) {
        switcher.perform(shortcut)
    }

    fileprivate func handle(event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = withUnsafeMutablePointer(to: &hotKeyID) { pointer in
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                pointer
            )
        }
        guard status == noErr,
              hotKeyID.signature == Self.signature,
              let shortcut = shortcutsByID[hotKeyID.id] else {
            return OSStatus(eventNotHandledErr)
        }

        let eventKind = GetEventKind(event)
        if eventKind == UInt32(kEventHotKeyReleased) {
            pressGate.release(hotKeyID.id)
            return noErr
        }
        if eventKind == UInt32(kEventHotKeyPressed),
           pressGate.acceptPress(hotKeyID.id) {
            switcher.perform(shortcut)
        }
        return noErr
    }
}

struct HotKeyPressGate {
    private var heldHotKeyIDs = Set<UInt32>()

    mutating func acceptPress(_ id: UInt32) -> Bool {
        heldHotKeyIDs.insert(id).inserted
    }

    mutating func release(_ id: UInt32) {
        heldHotKeyIDs.remove(id)
    }

    mutating func reset() {
        heldHotKeyIDs.removeAll()
    }
}
