import AppKit
import CoreAudio
import CoreMediaIO

/// Detects "don't embarrass me" moments: camera on, mic in use, or a full-screen app in front.
/// Reads only on/off state from the OS — never audio, video or window contents.
enum HushReason: Equatable {
    case away, paused, camera, call, fullScreen

    var message: String {
        switch self {
        case .away: "Paused while you're away 💤"
        case .paused: "The crew is on a break ☕"
        case .camera: "Hushed — you're on camera 🤫"
        case .call: "Hushed — you're on a call 🤫"
        case .fullScreen: "Hushed — you're in full screen 🤫"
        }
    }
}

final class HushDetector {
    private(set) var reason: HushReason?
    private var lastPoll = Date.distantPast

    func poll(enabled: Bool, now: Date = Date()) {
        guard enabled else { reason = nil; return }
        guard now.timeIntervalSince(lastPoll) >= 2 else { return }
        lastPoll = now
        if Self.cameraInUse() { reason = .camera }
        else if Self.micInUse() { reason = .call }
        else if Self.frontmostIsFullScreen() { reason = .fullScreen }
        else { reason = nil }
    }

    static func cameraInUse() -> Bool {
        var addr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, &size) == noErr,
              size > 0 else { return false }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, size, &used, &ids) == noErr
        else { return false }
        for id in ids {
            var running: UInt32 = 0
            var rAddr = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
            var rUsed: UInt32 = 0
            if CMIOObjectGetPropertyData(id, &rAddr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &rUsed, &running) == noErr,
               running != 0 { return true }
        }
        return false
    }

    /// Any process capturing audio input (macOS 14.2+ per-process API; music playback doesn't count).
    static func micInUse() -> Bool {
        guard #available(macOS 14.2, *) else { return false }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return false }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return false }
        let me = getpid()
        for id in ids {
            var pid: pid_t = 0
            var pSize = UInt32(MemoryLayout<pid_t>.size)
            var pAddr = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID,
                                                   mScope: kAudioObjectPropertyScopeGlobal,
                                                   mElement: kAudioObjectPropertyElementMain)
            if AudioObjectGetPropertyData(id, &pAddr, 0, nil, &pSize, &pid) == noErr, pid == me { continue }
            var running: UInt32 = 0
            var rSize = UInt32(MemoryLayout<UInt32>.size)
            var rAddr = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningInput,
                                                   mScope: kAudioObjectPropertyScopeGlobal,
                                                   mElement: kAudioObjectPropertyElementMain)
            if AudioObjectGetPropertyData(id, &rAddr, 0, nil, &rSize, &running) == noErr, running != 0 { return true }
        }
        return false
    }

    /// Frontmost app owns a normal-layer window the exact size of a screen (menu bar included).
    /// Uses window bounds and owner only, which need no Screen Recording permission.
    static func frontmostIsFullScreen() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid(),
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        let screenSizes = NSScreen.screens.map(\.frame.size)
        for w in list {
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == front.processIdentifier,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict) else { continue }
            if screenSizes.contains(where: { $0 == bounds.size }) { return true }
        }
        return false
    }
}
