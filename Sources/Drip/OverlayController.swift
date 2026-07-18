import AppKit
import SwiftUI
import DripCore

/// Borderless, transparent, never-key panel. `clickThrough` panels pass every click to the app beneath.
final class OverlayPanel: NSPanel {
    init(frame: NSRect, level: NSWindow.Level, clickThrough: Bool) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.level = level
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = clickThrough
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .none
    }
    override var canBecomeKey: Bool { !ignoresMouseEvents }
    override var canBecomeMain: Bool { false }
}

/// Buttons in a non-activating panel should respond to the very first click.
final class FirstMouseHostingView<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// One click-through overlay per display, the corner toast, and the full-screen takeover on the main display.
@MainActor
final class OverlayController {
    private let model: AppModel
    private let store = OverlayStore()
    private var panels: [OverlayPanel] = []
    private var linePanels: [OverlayPanel] = []
    private var toast: OverlayPanel?
    private var takeover: OverlayPanel?

    static let overlayLevel = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue)
    static let toastLevel = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)

    init(model: AppModel) {
        self.model = model
        rebuild()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.rebuild() }
        }
    }

    /// The primary display (the one with the menu bar), fixed — NSScreen.main follows keyboard focus.
    private var mainScreen: NSScreen { NSScreen.screens[0] }

    func rebuild() {
        panels.forEach { $0.orderOut(nil) }
        let main = mainScreen
        panels = NSScreen.screens.map { screen in
            let p = OverlayPanel(frame: screen.frame, level: Self.overlayLevel, clickThrough: true)
            p.contentView = NSHostingView(rootView: OverlayRoot(store: store, menuBarHeight: Self.menuBarHeight(screen),
                                                                isMain: screen == main, screenFrame: screen.frame))
            p.setFrame(screen.frame, display: false)
            return p
        }
        linePanels.forEach { $0.orderOut(nil) }
        linePanels = NSScreen.screens.map { screen in
            let f = NSRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width, height: 5)
            let p = OverlayPanel(frame: f, level: Self.overlayLevel, clickThrough: true)
            p.contentView = NSHostingView(rootView: BottomWaterLine(store: store))
            p.setFrame(f, display: false)
            return p
        }

        toast?.orderOut(nil)
        let t = OverlayPanel(frame: NSRect(x: 0, y: 0, width: 440, height: 130), level: Self.toastLevel, clickThrough: false)
        let host = FirstMouseHostingView(rootView: ToastView(model: model))
        host.sizingOptions = []   // keep the panel a fixed size; don't collapse to empty content
        t.contentView = host
        toast = t

        takeover?.orderOut(nil)
        let to = OverlayPanel(frame: main.frame, level: Self.toastLevel, clickThrough: false)
        let thost = FirstMouseHostingView(rootView: TakeoverView(model: model))
        thost.sizingOptions = []
        to.contentView = thost
        to.setFrame(main.frame, display: false)
        takeover = to
        update()
    }

    static func menuBarHeight(_ screen: NSScreen) -> CGFloat {
        let fromFrame = screen.frame.maxY - screen.visibleFrame.maxY
        return max(fromFrame, screen.safeAreaInsets.top, NSStatusBar.system.thickness, 24)
    }

    func update() {
        let m = model
        var scene = OverlayScene()
        scene.presentation = m.presentation
        scene.mood = m.mood
        scene.bottomLevel = m.settings.bottomWaterLine && m.waterEnabled ? m.state.hydration.level : nil
        scene.celebration = m.celebration
        scene.gagStartedAt = m.gagStartedAt
        scene.line = m.line
        // Quantise the bottom line so it redraws only on ≥1% changes.
        if let l = scene.bottomLevel { scene.bottomLevel = (l * 100).rounded() / 100 }
        store.set(scene)

        show(panels, scene.needsOverlay)
        show(linePanels, scene.bottomLevel != nil && !scene.needsOverlay)
        updateToast()
        updateTakeover()
        updateHotKeys(scene)
    }

    /// Esc makes whatever's on screen go away (takeover → skip, anything gentler → later);
    /// Space holds in the hold-to-finish games. Registered only while a nudge is actually showing.
    private func updateHotKeys(_ scene: OverlayScene) {
        let p = model.presentation
        let onScreen = p?.showing == true && (scene.paints || p?.wantsToast == true)
        let holdGame = p?.has(.miniGame) == true && p?.kind != .water
        let keys = HotKeys.shared
        keys.onEscape = { [weak self] in
            guard let self, let p = self.model.presentation else { return }
            if p.blocksScreen { self.model.skip() } else { self.model.snooze() }
        }
        keys.onSpace = { down in HoldState.shared.holding = down }
        keys.update(escape: onScreen, space: holdGame)
    }

    private func show(_ ps: [OverlayPanel], _ visible: Bool) {
        for p in ps {
            if visible, !p.isVisible { p.orderFrontRegardless() }
            if !visible, p.isVisible { p.orderOut(nil) }
        }
    }

    private var toastHideWork: DispatchWorkItem?
    private var takeoverHideWork: DispatchWorkItem?

    /// Panels linger a moment after their nudge ends so the SwiftUI exit animation can play.
    private func hide(_ panel: NSPanel, after delay: Double, work: inout DispatchWorkItem?, then: (() -> Void)? = nil) {
        guard panel.isVisible, work == nil else { return }
        let w = DispatchWorkItem { [weak panel] in panel?.orderOut(nil); then?() }
        work = w
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
    }

    private func updateToast() {
        guard let toast else { return }
        if model.presentation?.wantsToast == true {
            toastHideWork?.cancel(); toastHideWork = nil
            let v = mainScreen.visibleFrame
            let origin = NSPoint(x: v.maxX - toast.frame.width - 8, y: v.maxY - toast.frame.height - 4)
            if toast.frame.origin != origin { toast.setFrameOrigin(origin) }
            if !toast.isVisible { toast.orderFrontRegardless() }
        } else {
            hide(toast, after: 0.35, work: &toastHideWork) { [weak self] in self?.toastHideWork = nil }
        }
    }

    /// Takeovers come to the front; keys are handled by `HotKeys` so they work even if focus doesn't move.
    private func updateTakeover() {
        guard let takeover else { return }
        let up = model.presentation?.blocksScreen == true
        if up {
            takeoverHideWork?.cancel(); takeoverHideWork = nil
            takeover.ignoresMouseEvents = false
            if !takeover.isVisible {
                takeover.setFrame(mainScreen.frame, display: true)
                takeover.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        } else if takeover.isVisible {
            HoldState.shared.holding = false
            // Clicks pass through while it shrinks away.
            takeover.ignoresMouseEvents = true
            hide(takeover, after: 0.5, work: &takeoverHideWork) { [weak self] in
                self?.takeoverHideWork = nil
                self?.takeover?.ignoresMouseEvents = false
            }
        }
    }
}
