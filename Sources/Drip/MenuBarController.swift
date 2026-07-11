import AppKit
import SwiftUI
import DripCore

/// A panel that never activates the app: opening the crew popover keeps the frontmost app's
/// menus in the menu bar (a real NSPopover makes Nudgelings active, and its empty menu replaces them).
final class PopoverPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }
    // Key (for Esc and cursor updates) without activating the app — that's what .nonactivatingPanel buys.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Where the arrow points, in the panel's coordinates.
@MainActor
final class PopoverLayout: ObservableObject {
    @Published var arrowX: CGFloat = 180
}

/// Toy-style chrome around the popover content: ink-outlined card, hard shadow, little arrow.
struct PopoverChrome<Content: View>: View {
    @ObservedObject var layout: PopoverLayout
    @ViewBuilder var content: Content
    static var arrowHeight: CGFloat { 10 }

    var body: some View {
        VStack(spacing: -Theme.stroke) {
            PopoverArrow()
                .fill(Theme.paper)
                .overlay(PopoverArrow().stroke(Theme.outline, style: StrokeStyle(lineWidth: Theme.stroke, lineJoin: .round)))
                .frame(width: 22, height: Self.arrowHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .offset(x: layout.arrowX - 11)
                .zIndex(1)
            content
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .toyCard(Theme.paper, radius: 18, shadow: 5)
        }
        .padding(.horizontal, 6).padding(.bottom, 10)
    }
}

struct PopoverArrow: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        return p
    }
}

/// A Nudgeling in the menu bar; click for the crew popover.
@MainActor
final class MenuBarController: NSObject {
    private let model: AppModel
    private let item = NSStatusBar.system.statusItem(withLength: 26)
    private let panel = PopoverPanel()
    private let layout = PopoverLayout()
    private var host: FirstMouseHostingView<PopoverChrome<MenuPopover>>?
    private var outsideMonitor: Any?
    private var insideMonitor: Any?
    private var keyMonitor: Any?
    private var wiggleTimer: Timer?
    private var lastDrawn: FaceIcon.Key?
    private var maxHeight: CGFloat = 800
    var openMain: ((Navigation.Page) -> Void)?

    init(model: AppModel) {
        self.model = model
        super.init()
        item.button?.target = self
        item.button?.action = #selector(toggle)
        item.button?.toolTip = "Nudgelings"
        update()
    }

    private var isOpen: Bool { panel.isVisible }

    private func popoverView() -> PopoverChrome<MenuPopover> {
        PopoverChrome(layout: layout) {
            MenuPopover(model: model,
                        openMain: { [weak self] page in self?.close(); self?.openMain?(page) },
                        share: { [weak self] in self?.close(); self?.openMain?(.share(.today)) },
                        maxHeight: maxHeight,
                        openID: UUID())
        }
    }

    @objc func toggle() {
        if isOpen { close() } else { open() }
    }

    private func open() {
        guard let b = item.button, let bw = b.window else { return }
        // With a menu bar on every display, each shows its own copy of the icon: anchor to the one clicked.
        let clicked = NSApp.currentEvent.flatMap { e in e.window.map { ($0, e) } }
        let iconRect: NSRect
        if let (w, _) = clicked, w !== panel, w.frame.width < 200, w.frame.height < 60 {
            iconRect = w.frame
        } else {
            iconRect = bw.convertToScreen(b.convert(b.bounds, to: nil))
        }
        // The screen whose menu bar holds the icon (match on x; the status window can sit just above the frame).
        let screen = NSScreen.screens.first { $0.frame.minX <= iconRect.midX && iconRect.midX < $0.frame.maxX
            && abs($0.frame.maxY - iconRect.maxY) < 80 } ?? bw.screen ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        maxHeight = visible.height - PopoverChrome<MenuPopover>.arrowHeight - 30

        let h = FirstMouseHostingView(rootView: popoverView())
        host = h
        panel.contentView = h
        h.layoutSubtreeIfNeeded()
        let size = h.fittingSize

        // Hang from the menu bar, centred on the icon, kept fully on this screen.
        let top = min(iconRect.minY - 2, visible.maxY)
        var x = iconRect.midX - size.width / 2
        x = min(max(x, visible.minX + 6), visible.maxX - size.width - 6)
        let y = max(top - size.height, visible.minY + 6)
        layout.arrowX = min(max(iconRect.midX - x - 6, 24), size.width - 36)
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: top - y), display: true)

        Motion.shared.popoverOpen = true
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()   // key, not active: the frontmost app keeps its menus
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            panel.animator().alphaValue = 1
        }
        item.button?.highlight(true)

        // Close on any click outside (global monitors see other apps' clicks; no permission needed for mouse)
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
        // …and on clicks in our own other windows (the main window, onboarding), which global monitors don't see.
        insideMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] e in
            guard let self, e.window !== self.panel, e.window !== self.item.button?.window else { return e }
            Task { @MainActor in self.close() }
            return e
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] e in
            if e.keyCode == 53, self?.isOpen == true { self?.close(); return nil }
            return e
        }
    }

    /// Content can change height while open (a reminder fires, a habit turns on): keep it hanging from the top.
    private func relayout() {
        guard isOpen, let h = host else { return }
        let size = h.fittingSize
        let top = panel.frame.maxY
        if abs(size.height - panel.frame.height) > 1 {
            panel.setFrame(NSRect(x: panel.frame.minX, y: top - size.height, width: size.width, height: size.height), display: true)
        }
    }

    func close() {
        guard isOpen else { return }
        if let m = outsideMonitor { NSEvent.removeMonitor(m) }
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        if let m = insideMonitor { NSEvent.removeMonitor(m) }
        outsideMonitor = nil; keyMonitor = nil; insideMonitor = nil
        item.button?.highlight(false)
        Motion.shared.popoverOpen = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, !Motion.shared.popoverOpen else { return }
                self.panel.orderOut(nil)
                self.panel.contentView = nil
                self.host = nil
            }
        })
    }

    func update() {
        relayout()
        // Also wiggle while something is waiting out a hush, so you know Drip hasn't forgotten.
        let wiggling = model.hasReminder || (model.hushReason != nil && model.hushReason != .paused && !model.state.queued.isEmpty)
        if wiggling, wiggleTimer == nil {
            wiggleTimer = Timer.scheduledTimer(withTimeInterval: 1 / 15, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.redraw() }
            }
        } else if !wiggling, let t = wiggleTimer {
            t.invalidate()
            wiggleTimer = nil
        }
        redraw()
    }

    private func redraw() {
        let kind = model.activeKind ?? (model.waterEnabled ? .water : model.settings.enabledKinds.first ?? .water)
        let expression: Expression = model.activeKind != nil ? .worried
            : kind == .water ? (model.waterEnabled ? model.mood.expression : .happy) : .happy
        let frame = wiggleTimer != nil ? Int(Date().timeIntervalSinceReferenceDate * 15) % FaceIcon.frames : 0
        let key = FaceIcon.Key(kind: kind, expression: expression, frame: frame, badge: model.hasReminder,
                               sleepy: model.hushReason == .paused)
        guard key != lastDrawn else { return }
        lastDrawn = key
        item.button?.image = FaceIcon.image(key)
    }
}

/// A Nudgeling in the menu bar. Whoever is due hops and wiggles; otherwise Drip shows your hydration.
@MainActor
enum FaceIcon {
    struct Key: Hashable {
        var kind: HabitKind
        var expression: Expression
        var frame: Int
        var badge: Bool
        var sleepy: Bool
    }

    static let frames = 16
    private static var cache: [Key: NSImage] = [:]

    static func image(_ key: Key) -> NSImage {
        if let img = cache[key] { return img }
        let phase = Double(key.frame) / Double(frames)
        let hop = key.frame == 0 ? 0 : abs(sin(phase * .pi * 2)) * 2.5
        let tilt = key.frame == 0 ? 0 : sin(phase * .pi * 2) * 10
        let view = ZStack(alignment: .topTrailing) {
            CharacterView(kind: key.kind, expression: key.sleepy ? .sleepy : key.expression, size: 21, shadow: false)
                .rotationEffect(.degrees(tilt), anchor: .bottom)
                .offset(y: -hop)
                .frame(width: 22, height: 22, alignment: .bottom)
            if key.badge {
                Circle().fill(Theme.coral).overlay(Circle().strokeBorder(Theme.ink, lineWidth: 1))
                    .frame(width: 6, height: 6).offset(x: -1, y: 1)
            }
        }
        .frame(width: 22, height: 22)
        let r = ImageRenderer(content: view)
        r.scale = 2
        let img = r.nsImage ?? NSImage()
        img.size = NSSize(width: 22, height: 22)
        img.isTemplate = false
        cache[key] = img
        return img
    }
}
