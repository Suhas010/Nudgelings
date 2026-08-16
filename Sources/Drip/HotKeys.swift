import Carbon.HIToolbox
import AppKit

/// System-wide Esc / Space while a nudge is on screen.
///
/// Nudgelings is a menu-bar app, so it's almost never the focused app: plain key monitors miss Esc.
/// Carbon hot keys are delivered no matter who's focused and need no Accessibility permission.
/// They're registered only while something is showing, so Esc/Space are back to normal otherwise.
@MainActor
final class HotKeys {
    static let shared = HotKeys()

    var onEscape: (() -> Void)?
    var onSpace: ((_ down: Bool) -> Void)?

    private var escRef: EventHotKeyRef?
    private var spaceRef: EventHotKeyRef?
    private var handler: EventHandlerRef?

    private init() {
        var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let down = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    switch id.id {
                    case 1: if down { HotKeys.shared.onEscape?() }
                    case 2: HotKeys.shared.onSpace?(down)
                    default: break
                    }
                }
            }
            return noErr
        }, 2, &types, nil, &handler)
    }

    /// Esc while any nudge is on screen; Space only during hold-to-finish mini-games.
    func update(escape: Bool, space: Bool) {
        if escape, escRef == nil { escRef = register(key: kVK_Escape, id: 1) }
        if !escape, let r = escRef { UnregisterEventHotKey(r); escRef = nil }
        if space, spaceRef == nil { spaceRef = register(key: kVK_Space, id: 2) }
        if !space, let r = spaceRef { UnregisterEventHotKey(r); spaceRef = nil; onSpace?(false) }
    }

    private func register(key: Int, id: UInt32) -> EventHotKeyRef? {
        var ref: EventHotKeyRef?
        let hk = EventHotKeyID(signature: OSType(0x4E55_4447), id: id)   // 'NUDG'
        let status = RegisterEventHotKey(UInt32(key), 0, hk, GetApplicationEventTarget(), 0, &ref)
        return status == noErr ? ref : nil
    }
}
