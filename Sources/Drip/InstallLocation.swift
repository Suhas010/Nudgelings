import AppKit

/// Opened straight from the DMG, or from a download macOS translocated, the app runs from a temporary,
/// read-only path: "Open at login" and the next launch would point at nothing. Offer to move it to
/// Applications before onboarding starts.
@MainActor
enum InstallLocation {
    static var needsMove: Bool {
        let path = Bundle.main.bundlePath
        guard path.hasSuffix(".app") else { return false }          // unbundled dev runs
        return path.hasPrefix("/Volumes/") || path.contains("/AppTranslocation/")
    }

    /// Returns true when a moved copy is launching and this one should stop here.
    static func offerMoveIfNeeded() -> Bool {
        guard needsMove else { return false }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Move Nudgelings to Applications?"
        alert.informativeText = "It's running from the disk image right now. From Applications it can open at login, and it won't vanish when you eject the disk image."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        // An older copy may already be running from Applications (an upgrade): let it go first.
        if let id = Bundle.main.bundleIdentifier {
            for other in NSRunningApplication.runningApplications(withBundleIdentifier: id) where other != .current {
                other.terminate()
            }
        }
        let source = Bundle.main.bundleURL
        let name = source.lastPathComponent
        let fm = FileManager.default
        let targets = [URL(fileURLWithPath: "/Applications"),
                       fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        for dir in targets {
            let dest = dir.appendingPathComponent(name)
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                if fm.fileExists(atPath: dest.path) { try fm.trashItem(at: dest, resultingItemURL: nil) }
                try fm.copyItem(at: source, to: dest)
            } catch {
                continue                                             // e.g. no write access: try ~/Applications
            }
            let config = NSWorkspace.OpenConfiguration()
            config.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: dest, configuration: config) { _, _ in
                Task { @MainActor in NSApp.terminate(nil) }
            }
            return true
        }
        let failed = NSAlert()
        failed.messageText = "Couldn't move Nudgelings"
        failed.informativeText = "Drag it into your Applications folder from the disk image, then open it from there."
        failed.runModal()
        return false
    }
}
