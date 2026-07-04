import AppKit
import SwiftUI
import DripCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var model: AppModel!
    private var menuBar: MenuBarController!
    private var overlay: OverlayController!
    private var windows: [String: NSWindow] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        Fonts.register()
        model = AppModel()
        overlay = OverlayController(model: model)
        menuBar = MenuBarController(model: model)
        menuBar.openMain = { [weak self] page in self?.showMain(page) }
        model.replayOnboarding = { [weak self] in
            self?.windows["onboarding"] = nil
            self?.showOnboarding()
        }
        model.onUpdate = { [weak self] in
            self?.overlay.update()
            self?.menuBar.update()
        }
        observeAway()
        model.start()
        if !model.settings.onboarded { showOnboarding() }
        runDevTryFlag()
    }

    /// Dev aid: `--try <habit> <nudge[,nudge]>` previews on launch, e.g. `--try water gag,menuShow`.
    private func runDevTryFlag() {
        let args = CommandLine.arguments
        if args.contains("--main") { showMain() }
        if args.contains("--popover") { DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.menuBar.toggle() } }
        guard let i = args.firstIndex(of: "--try"), i + 2 < args.count, let kind = HabitKind(rawValue: args[i + 1]) else { return }
        let types = args[i + 2].split(separator: ",").compactMap { NudgeType(rawValue: String($0)) }
        model.previewNudges(kind, types: types.isEmpty ? nil : types)
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.save()
    }

    // MARK: Away (lock / sleep) → treated like hush

    // Locked and asleep are tracked separately: waking the display while still locked isn't "back".
    private var locked = false
    private var asleep = false

    private func observeAway() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.locked = true; self?.syncAway() }
        }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.locked = false; self?.syncAway() }
        }
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.asleep = true; self?.syncAway() }
            }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.asleep = false; self?.syncAway() }
            }
        }
    }

    private func syncAway() { model.setAway(locked || asleep) }

    // MARK: Windows

    func showMain(_ page: Navigation.Page = .crew) {
        Navigation.shared.page = page
        show(id: "main", title: "Nudgelings", size: NSSize(width: 1000, height: 720)) {
            MainWindow(model: self.model)
        }
    }

    func showOnboarding() {
        show(id: "onboarding", title: "Welcome to Nudgelings", size: NSSize(width: 580, height: 650)) {
            OnboardingView(model: self.model) { [weak self] in self?.windows["onboarding"]?.close() }
        }
    }

    private func show<V: View>(id: String, title: String, size: NSSize, @ViewBuilder content: () -> V) {
        if let w = windows[id] {
            Motion.shared.visibleWindows.insert(id)
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = title
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: content()
            .modifier(PauseWhenHidden(id: id)))
        w.center()
        w.makeKeyAndOrderFront(nil)
        windows[id] = w
        // Characters stop animating while the window is closed or fully covered.
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: w, queue: .main) { n in
            guard let w = n.object as? NSWindow else { return }
            Task { @MainActor in
                if w.occlusionState.contains(.visible) { Motion.shared.visibleWindows.insert(id) }
                else { Motion.shared.visibleWindows.remove(id) }
            }
        }
        nc.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            Task { @MainActor in Motion.shared.visibleWindows.remove(id) }
        }
        Motion.shared.visibleWindows.insert(id)
        NSApp.activate(ignoringOtherApps: true)
    }

}
